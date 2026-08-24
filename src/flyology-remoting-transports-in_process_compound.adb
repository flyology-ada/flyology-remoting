with Flyology_Wire;
with Flyology.Remoting.Compound_Test_Hooks;

package body Flyology.Remoting.Transports.In_Process_Compound is
   package Buffers renames Flyology.Buffers;

   use type Ada.Streams.Stream_Element_Count;
   use type Channels.Transfer_Metadata;
   use type Channels.Try_Receive_Result;
   use type Channels.Try_Send_Result;
   use type Flyology_Wire.Byte_Count;
   use type Headers.Encode_Status;

   No_Header_Slot : constant Natural := 0;

   protected body Received_Release_Gate is
      procedure Release
        (Payload : in out Buffers.Unique_Buffer;
         Header  : in out Buffers.Unique_Buffer)
      is
      begin
         Buffers.Release (Payload);
         Buffers.Release (Header);
      end Release;
   end Received_Release_Gate;

   protected body Compound_State is
      procedure Try_Begin_Build
        (Queue : Channels.Channel; Ticket : in out Builder_Ticket; Result : out Build_Start_Result)
      is
         Queue_State : constant Channels.Snapshot := Channels.Current (Queue);
      begin
         if Ticket.Held then
            raise Program_Error with "compound builder ticket was already held";
         elsif Stopped or else Queue_State.Closed then
            Result := Build_Closed;
         elsif Active_Builders = Maximum_Concurrent_Builders then
            Result := Build_Limit;
         else
            Active_Builders := Active_Builders + 1;
            Ticket.Held := True;
            Result := Build_Started;
         end if;
      end Try_Begin_Build;

      procedure Abandon_Build (Ticket : in out Builder_Ticket) is
      begin
         if Ticket.Held then
            if Active_Builders = 0 then
               raise Program_Error with "compound builder accounting underflow";
            end if;
            Active_Builders := Active_Builders - 1;
            Ticket.Held := False;
         end if;
      end Abandon_Build;

      procedure Reset_Build (Header : in out Drivers.Detached_Buffer; Ticket : in out Builder_Ticket) is
      begin
         Drivers.Release (Header);
         Abandon_Build (Ticket);
      end Reset_Build;

      procedure Allocate_Header_Slot (Slot : out Header_Slot) is
      begin
         if Free_Count > 0 then
            Slot := Header_Slot (Free_Slots (Free_Count));
            Free_Slots (Free_Count) := No_Header_Slot;
            Free_Count := Free_Count - 1;
         elsif Next_Unused <= Header_Slot'Last then
            Slot := Header_Slot (Next_Unused);
            Next_Unused := Next_Unused + 1;
         else
            raise Program_Error with "compound header slots exhausted below queue capacity";
         end if;
         if Active (Slot) then
            raise Program_Error with "compound header slot was already active";
         end if;
         Active (Slot) := True;
      end Allocate_Header_Slot;

      procedure Release_Header_Slot (Slot : Header_Slot) is
      begin
         if not Active (Slot) or else Drivers.Has_Buffer (Header_Leases (Slot)) then
            raise Program_Error with "compound header slot released in an invalid state";
         end if;
         Active (Slot) := False;
         Header_Values (Slot) := Headers.No_Header;
         Free_Count := Free_Count + 1;
         Free_Slots (Free_Count) := Slot;
      end Release_Header_Slot;

      procedure Finish_Build (Ticket : in out Builder_Ticket) is
      begin
         Abandon_Build (Ticket);
      end Finish_Build;

      procedure Try_Commit
        (Queue   : in out Channels.Channel;
         Header  : in out Drivers.Detached_Buffer;
         Payload : in out Buffers.Unique_Buffer;
         Value   : Headers.Header;
         Ticket  : in out Builder_Ticket;
         Result  : out Try_Send_Result)
      is
         Queue_State : constant Channels.Snapshot := Channels.Current (Queue);
         Queue_Result : Channels.Try_Send_Result;
         Slot         : Header_Slot;
         Slot_Allocated : Boolean := False;
      begin
         if not Ticket.Held
           or else not Drivers.Has_Buffer (Header)
           or else not Buffers.Has_Buffer (Payload)
         then
            raise Program_Error with "invalid compound commit ownership";
         elsif Queue_State.Closed then
            Reset_Build (Header, Ticket);
            Result := Send_Closed;
            return;
         elsif Queue_State.Pending = Queue_Capacity then
            Reset_Build (Header, Ticket);
            Result := Backpressure;
            return;
         end if;

         Allocate_Header_Slot (Slot);
         Slot_Allocated := True;
         if Flyology.Remoting.Compound_Test_Hooks.Enabled then
            Flyology.Remoting.Compound_Test_Hooks.Raise_If_Armed
              (Flyology.Remoting.Compound_Test_Hooks.After_Header_Slot_Allocation);
         end if;
         Drivers.Move (Header, Header_Leases (Slot));
         if Flyology.Remoting.Compound_Test_Hooks.Enabled then
            Flyology.Remoting.Compound_Test_Hooks.Raise_If_Armed
              (Flyology.Remoting.Compound_Test_Hooks.After_Header_Move);
         end if;
         Header_Values (Slot) := Value;
         Channels.Try_Send_Move
           (Queue,
            Payload,
            Queue_Result,
            Channels.Transfer_Metadata (Slot));
         if Flyology.Remoting.Compound_Test_Hooks.Enabled then
            Flyology.Remoting.Compound_Test_Hooks.Raise_If_Armed
              (Flyology.Remoting.Compound_Test_Hooks.After_Queue_Transfer);
         end if;

         case Queue_Result is
            when Channels.Item_Sent =>
               Result := Message_Accepted;
            when Channels.Channel_Full =>
               Drivers.Move (Header_Leases (Slot), Header);
               Release_Header_Slot (Slot);
               Result := Backpressure;
            when Channels.Send_Closed =>
               Drivers.Move (Header_Leases (Slot), Header);
               Release_Header_Slot (Slot);
               Result := Send_Closed;
         end case;
         if Queue_Result = Channels.Item_Sent then
            Finish_Build (Ticket);
         else
            Reset_Build (Header, Ticket);
         end if;
      exception
         when others =>
            if Slot_Allocated and then Buffers.Has_Buffer (Payload) then
               if Drivers.Has_Buffer (Header_Leases (Slot)) then
                  Drivers.Move (Header_Leases (Slot), Header);
               end if;
               Release_Header_Slot (Slot);
            end if;
            if not Buffers.Has_Buffer (Payload) then
               Finish_Build (Ticket);
            else
               Reset_Build (Header, Ticket);
            end if;
            raise;
      end Try_Commit;

      procedure Try_Commit_Forward
        (Queue      : in out Channels.Channel;
         Header     : in out Drivers.Detached_Buffer;
         Value      : in out Received_Message;
         New_Header : Headers.Header;
         Ticket     : in out Builder_Ticket;
         Result     : out Try_Send_Result)
      is
         Queue_State  : constant Channels.Snapshot := Channels.Current (Queue);
         Queue_Result : Channels.Try_Send_Result;
         Slot         : Header_Slot;
         Slot_Allocated : Boolean := False;
      begin
         if not Ticket.Held
           or else not Drivers.Has_Buffer (Header)
           or else not Buffers.Has_Buffer (Value.Payload_Buffer)
           or else not Buffers.Has_Buffer (Value.Header_Buffer)
         then
            raise Program_Error with "invalid compound forward ownership";
         elsif Queue_State.Closed then
            Reset_Build (Header, Ticket);
            Result := Send_Closed;
            return;
         elsif Queue_State.Pending = Queue_Capacity then
            Reset_Build (Header, Ticket);
            Result := Backpressure;
            return;
         end if;

         Allocate_Header_Slot (Slot);
         Slot_Allocated := True;
         if Flyology.Remoting.Compound_Test_Hooks.Enabled then
            Flyology.Remoting.Compound_Test_Hooks.Raise_If_Armed
              (Flyology.Remoting.Compound_Test_Hooks.After_Header_Slot_Allocation);
         end if;
         Drivers.Move (Header, Header_Leases (Slot));
         if Flyology.Remoting.Compound_Test_Hooks.Enabled then
            Flyology.Remoting.Compound_Test_Hooks.Raise_If_Armed
              (Flyology.Remoting.Compound_Test_Hooks.After_Header_Move);
         end if;
         Header_Values (Slot) := New_Header;
         Channels.Try_Send_Move
           (Queue,
            Value.Payload_Buffer,
            Queue_Result,
            Channels.Transfer_Metadata (Slot));
         if Flyology.Remoting.Compound_Test_Hooks.Enabled then
            Flyology.Remoting.Compound_Test_Hooks.Raise_If_Armed
              (Flyology.Remoting.Compound_Test_Hooks.After_Queue_Transfer);
         end if;

         case Queue_Result is
            when Channels.Item_Sent =>
               Buffers.Release (Value.Header_Buffer);
               Value.Header_Value := Headers.No_Header;
               Result := Message_Accepted;
            when Channels.Channel_Full =>
               Drivers.Move (Header_Leases (Slot), Header);
               Release_Header_Slot (Slot);
               Result := Backpressure;
            when Channels.Send_Closed =>
               Drivers.Move (Header_Leases (Slot), Header);
               Release_Header_Slot (Slot);
               Result := Send_Closed;
         end case;
         if Queue_Result = Channels.Item_Sent then
            Finish_Build (Ticket);
         else
            Reset_Build (Header, Ticket);
         end if;
      exception
         when others =>
            if Slot_Allocated then
               if Buffers.Has_Buffer (Value.Payload_Buffer) then
                  if Drivers.Has_Buffer (Header_Leases (Slot)) then
                     Drivers.Move (Header_Leases (Slot), Header);
                  end if;
                  Release_Header_Slot (Slot);
               elsif Drivers.Has_Buffer (Header_Leases (Slot)) then
                  Buffers.Release (Value.Header_Buffer);
                  Value.Header_Value := Headers.No_Header;
               end if;
            end if;
            if not Buffers.Has_Buffer (Value.Payload_Buffer) then
               Finish_Build (Ticket);
            else
               Reset_Build (Header, Ticket);
            end if;
            raise;
      end Try_Commit_Forward;

      procedure Try_Receive
        (Queue : in out Channels.Channel; Target : in out Received_Message; Result : out Try_Receive_Result)
      is
         Queue_Result : Channels.Try_Receive_Result;
         Metadata     : Channels.Transfer_Metadata;
         Slot         : Header_Slot;
      begin
         if Buffers.Has_Buffer (Target.Payload_Buffer) or else Buffers.Has_Buffer (Target.Header_Buffer) then
            raise Program_Error with "compound receive target is occupied";
         end if;
         Channels.Try_Receive_Move (Queue, Target.Payload_Buffer, Queue_Result, Metadata);
         case Queue_Result is
            when Channels.Item_Received =>
               if Metadata = Channels.No_Metadata
                 or else Metadata > Channels.Transfer_Metadata (Header_Slot'Last)
               then
                  Buffers.Release (Target.Payload_Buffer);
                  Channels.Close (Queue);
                  raise Program_Error with "invalid compound header slot metadata";
               end if;
               Slot := Header_Slot (Metadata);
               if not Active (Slot) or else not Drivers.Has_Buffer (Header_Leases (Slot)) then
                  Buffers.Release (Target.Payload_Buffer);
                  Channels.Close (Queue);
                  raise Program_Error with "missing compound header lease";
               end if;
               Drivers.Move_To (Header_Leases (Slot), Target.Header_Buffer);
               Target.Header_Value := Header_Values (Slot);
               Release_Header_Slot (Slot);
               Result := Message_Received;
            when Channels.Channel_Empty =>
               Target.Header_Value := Headers.No_Header;
               Result := No_Message;
            when Channels.Receive_Closed =>
               Target.Header_Value := Headers.No_Header;
               Result := Receive_Closed;
         end case;
      end Try_Receive;

      procedure Close (Queue : in out Channels.Channel) is
      begin
         Stopped := True;
         Channels.Close (Queue);
      end Close;

      function Current (Queue : Channels.Channel) return Lane_Snapshot is
         Value : constant Channels.Snapshot := Channels.Current (Queue);
      begin
         return (Closed => Value.Closed, Pending => Value.Pending);
      end Current;
   end Compound_State;

   procedure Acquire (Item : in out Writable_Payload) is
   begin
      Buffers.Acquire (Item.Buffer);
   end Acquire;

   procedure Try_Acquire (Item : in out Writable_Payload; Acquired : out Boolean) is
   begin
      Buffers.Try_Acquire (Item.Buffer, Acquired);
   end Try_Acquire;

   procedure Release (Item : in out Writable_Payload) is
   begin
      Buffers.Release (Item.Buffer);
   end Release;

   procedure Release (Item : in out Received_Message) is
   begin
      Item.Release_Gate.Release (Item.Payload_Buffer, Item.Header_Buffer);
      Item.Header_Value := Headers.No_Header;
   end Release;

   function Has_Payload (Item : Writable_Payload) return Boolean is
     (Buffers.Has_Buffer (Item.Buffer));

   function Has_Message (Item : Received_Message) return Boolean is
     (Buffers.Has_Buffer (Item.Payload_Buffer)
      and then Buffers.Has_Buffer (Item.Header_Buffer)
      and then Headers.Is_Valid (Item.Header_Value));

   function Is_Vacant (Item : Received_Message) return Boolean is
     (not Buffers.Has_Buffer (Item.Payload_Buffer) and then not Buffers.Has_Buffer (Item.Header_Buffer));

   function Length (Item : Writable_Payload) return Natural is
     (Buffers.Length (Item.Buffer));

   function Length (Item : Received_Message) return Natural is
     (Buffers.Length (Item.Payload_Buffer));

   function Payload_Capacity (Item : Writable_Payload) return Positive is
     (Buffers.Buffer_Capacity (Item.Buffer));

   function Envelope (Item : Received_Message) return Headers.Header is
     (Item.Header_Value);

   procedure With_Writable_Data
     (Item    : in out Writable_Payload;
      Process :
        not null access procedure (Data : in out Ada.Streams.Stream_Element_Array; Length : in out Natural))
   is
   begin
      Buffers.With_Writable_Data (Item.Buffer, Process);
   end With_Writable_Data;

   procedure With_Readable_Data
     (Item : Writable_Payload; Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   is
   begin
      Buffers.With_Readable_Data (Item.Buffer, Process);
   end With_Readable_Data;

   procedure With_Readable_Data
     (Item : Received_Message; Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   is
   begin
      Buffers.With_Readable_Data (Item.Payload_Buffer, Process);
   end With_Readable_Data;

   procedure With_Encoded_Header
     (Item : Received_Message; Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   is
   begin
      Buffers.With_Readable_Data (Item.Header_Buffer, Process);
   end With_Encoded_Header;

   procedure Copy_From (Item : in out Writable_Payload; Data : Ada.Streams.Stream_Element_Array) is
   begin
      Buffers.Copy_From (Item.Buffer, Data);
   end Copy_From;

   function Payload_Length_Matches (Envelope : Headers.Header; Length : Natural) return Boolean is
     (Headers.Payload_Length (Envelope) = Flyology_Wire.Byte_Count (Length));

   function Is_Prepared (Item : Message_Builder) return Boolean is
     (Item.Ticket.Held
      and then Drivers.Has_Buffer (Item.Header_Lease)
      and then Headers.Is_Valid (Item.Header_Value));

   procedure Reset (Item : in out Message_Builder) is
   begin
      Item.Owner.State.Reset_Build (Item.Header_Lease, Item.Ticket);
      Item.Header_Value := Headers.No_Header;
   end Reset;

   procedure Disarm (Item : in out Prepare_Guard) is
   begin
      Item.Armed := False;
   end Disarm;

   overriding procedure Finalize (Item : in out Prepare_Guard) is
   begin
      if Item.Armed then
         begin
            Reset (Item.Builder.all);
         exception
            when others =>
               null;
         end;
      end if;
   end Finalize;

   procedure Prepare
     (Item : in out Message_Builder; Envelope : Headers.Header; Result : out Prepare_Result)
   is
      Header_Buffer : Buffers.Unique_Buffer (Item.Owner.Header_Storage);
      Guard         : Prepare_Guard (Item'Unchecked_Access);
      Acquired      : Boolean;
      Start_Result  : Build_Start_Result;

      procedure Encode_Header
        (Data : in out Ada.Streams.Stream_Element_Array; Length : in out Natural)
      is
         Written : Flyology_Wire.Octet_Count;
         Status  : Headers.Encode_Status;
      begin
         Headers.Encode (Envelope, Data, Written, Status);
         if Status /= Headers.Header_Encoded or else Written /= Headers.Encoded_Length then
            raise Program_Error with "validated compound header did not encode";
         end if;
         Length := Natural (Written);
      end Encode_Header;
   begin
      if not Headers.Is_Valid (Envelope) then
         Result := Prepare_Invalid_Header;
         return;
      end if;
      Item.Owner.State.Try_Begin_Build (Item.Owner.Queue, Item.Ticket, Start_Result);
      case Start_Result is
         when Build_Closed =>
            Result := Prepare_Closed;
            return;
         when Build_Limit =>
            Result := Prepare_Local_Resource_Exhausted;
            return;
         when Build_Started =>
            null;
      end case;
      if Flyology.Remoting.Compound_Test_Hooks.Enabled then
         Flyology.Remoting.Compound_Test_Hooks.Raise_If_Armed
           (Flyology.Remoting.Compound_Test_Hooks.After_Builder_Reservation);
      end if;
      Buffers.Try_Acquire (Header_Buffer, Acquired);
      if not Acquired then
         Item.Owner.State.Abandon_Build (Item.Ticket);
         Result := Prepare_Local_Resource_Exhausted;
         return;
      end if;
      begin
         Buffers.With_Writable_Data (Header_Buffer, Encode_Header'Access);
         Drivers.Move_From (Header_Buffer, Item.Header_Lease);
         Item.Header_Value := Envelope;
         Disarm (Guard);
         Result := Builder_Prepared;
      exception
         when others =>
            Reset (Item);
            raise;
      end;
   end Prepare;

   procedure Try_Commit
     (Item : in out Message_Builder; Value : in out Writable_Payload; Result : out Try_Send_Result)
   is
   begin
      if Value.Storage /= Item.Owner.Payload_Storage then
         raise Program_Error with "compound payload belongs to another builder lane pool";
      elsif not Payload_Length_Matches (Item.Header_Value, Buffers.Length (Value.Buffer)) then
         Reset (Item);
         Result := Payload_Length_Mismatch;
         return;
      end if;
      Item.Owner.State.Try_Commit
        (Item.Owner.Queue,
         Item.Header_Lease,
         Value.Buffer,
         Item.Header_Value,
         Item.Ticket,
         Result);
      Item.Header_Value := Headers.No_Header;
   end Try_Commit;

   procedure Try_Send
     (Item     : in out Lane;
      Envelope : Headers.Header;
      Value    : in out Writable_Payload;
      Result   : out Try_Send_Result)
   is
      Builder        : Message_Builder (Item'Unchecked_Access);
      Prepare_Status : Prepare_Result;
   begin
      if Value.Storage /= Item.Payload_Storage then
         raise Program_Error with "compound payload belongs to another lane pool";
      elsif not Headers.Is_Valid (Envelope) then
         Result := Invalid_Header;
      elsif not Payload_Length_Matches (Envelope, Buffers.Length (Value.Buffer)) then
         Result := Payload_Length_Mismatch;
      else
         Prepare (Builder, Envelope, Prepare_Status);
         case Prepare_Status is
            when Builder_Prepared =>
               Try_Commit (Builder, Value, Result);
            when Prepare_Invalid_Header =>
               Result := Invalid_Header;
            when Prepare_Local_Resource_Exhausted =>
               Result := Local_Resource_Exhausted;
            when Prepare_Closed =>
               Result := Send_Closed;
         end case;
      end if;
   end Try_Send;

   procedure Try_Forward
     (Item     : in out Lane;
      Envelope : Headers.Header;
      Value    : in out Received_Message;
      Result   : out Try_Send_Result)
   is
      Builder        : Message_Builder (Item'Unchecked_Access);
      Prepare_Status : Prepare_Result;
   begin
      if Value.Payload_Storage /= Item.Payload_Storage then
         raise Program_Error with "forwarded payload belongs to another lane pool";
      elsif not Headers.Is_Valid (Envelope) then
         Result := Invalid_Header;
      elsif not Payload_Length_Matches (Envelope, Buffers.Length (Value.Payload_Buffer)) then
         Result := Payload_Length_Mismatch;
      else
         Prepare (Builder, Envelope, Prepare_Status);
         case Prepare_Status is
            when Builder_Prepared =>
               Try_Commit_Forward (Builder, Value, Result);
            when Prepare_Invalid_Header =>
               Result := Invalid_Header;
            when Prepare_Local_Resource_Exhausted =>
               Result := Local_Resource_Exhausted;
            when Prepare_Closed =>
               Result := Send_Closed;
         end case;
      end if;
   end Try_Forward;

   procedure Try_Commit_Forward
     (Item : in out Message_Builder; Value : in out Received_Message; Result : out Try_Send_Result)
   is
   begin
      if Value.Payload_Storage /= Item.Owner.Payload_Storage then
         raise Program_Error with "forwarded payload belongs to another builder lane pool";
      elsif not Payload_Length_Matches (Item.Header_Value, Buffers.Length (Value.Payload_Buffer)) then
         Reset (Item);
         Result := Payload_Length_Mismatch;
         return;
      end if;
      Item.Owner.State.Try_Commit_Forward
        (Item.Owner.Queue,
         Item.Header_Lease,
         Value,
         Item.Header_Value,
         Item.Ticket,
         Result);
      Item.Header_Value := Headers.No_Header;
   end Try_Commit_Forward;

   procedure Try_Receive
     (Item   : in out Lane;
      Target : in out Received_Message;
      Result : out Try_Receive_Result)
   is
   begin
      if Target.Payload_Storage /= Item.Payload_Storage
        or else Target.Header_Storage /= Item.Header_Storage
      then
         raise Program_Error with "compound receive target belongs to another lane pool";
      elsif not Is_Vacant (Target) then
         raise Program_Error with "compound receive target is occupied";
      end if;
      Item.State.Try_Receive (Item.Queue, Target, Result);
   end Try_Receive;

   procedure Close (Item : in out Lane) is
   begin
      Item.State.Close (Item.Queue);
   end Close;

   function Current (Item : Lane) return Lane_Snapshot is
     (Item.State.Current (Item.Queue));

   overriding procedure Initialize (Item : in out Lane) is
   begin
      if Item.Header_Storage.Block_Size < Natural (Headers.Encoded_Length) then
         raise Invalid_Configuration with "compound header blocks are shorter than the V1 header";
      elsif Item.Header_Storage.Capacity < Queue_Capacity
        or else Item.Header_Storage.Capacity - Queue_Capacity < Maximum_Concurrent_Builders
      then
         raise Invalid_Configuration with "compound header pool cannot cover queue and builder leases";
      end if;
   end Initialize;

   overriding procedure Finalize (Item : in out Lane) is
      Target : Received_Message (Item.Payload_Storage, Item.Header_Storage);
      Result : Try_Receive_Result;
   begin
      begin
         Item.State.Close (Item.Queue);
         loop
            Item.State.Try_Receive (Item.Queue, Target, Result);
            exit when Result /= Message_Received;
            Release (Target);
         end loop;
      exception
         when others =>
            null;
      end;
   end Finalize;

   overriding procedure Finalize (Item : in out Message_Builder) is
   begin
      begin
         Reset (Item);
      exception
         when others =>
            null;
      end;
   end Finalize;

end Flyology.Remoting.Transports.In_Process_Compound;
