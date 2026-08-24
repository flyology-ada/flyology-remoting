package body Flyology.Remoting.Sessions.In_Process is
   use type Compound.Try_Receive_Result;
   use type Compound.Try_Send_Result;
   use type Messages.Message_ID;

   function Is_Valid_Message_Context
     (Message     : Messages.Message_ID;
      Correlation : Messages.Message_ID;
      Writer      : Flyology_Wire.Identities.Schema_Identity) return Boolean
   is
     (Messages.Is_Valid (Message)
      and then (Correlation = Messages.No_Message_ID or else Messages.Is_Valid (Correlation))
      and then Flyology_Wire.Identities.Is_Valid (Writer));

   function Make_Outbound_Header
     (Source      : Endpoints.Endpoint_Reference;
      Destination : Endpoints.Endpoint_Reference;
      Message     : Messages.Message_ID;
      Correlation : Messages.Message_ID;
      Writer      : Flyology_Wire.Identities.Schema_Identity;
      Length      : Natural) return Headers.Header
   is
   begin
      return
        Headers.Make_Header
          (Payload_Length          => Flyology_Wire.Byte_Count (Length),
           Message                 => Message,
           Correlation             => Correlation,
           Source_Slot             => Endpoints.Slot (Source),
           Source_Generation       => Endpoints.Generation (Source),
           Destination_Slot        => Endpoints.Slot (Destination),
           Destination_Generation  => Endpoints.Generation (Destination),
           Writer                  => Writer);
   end Make_Outbound_Header;

   procedure Map_Result (Value : Compound.Try_Send_Result; Result : out Try_Send_Result) is
   begin
      case Value is
         when Compound.Invalid_Header | Compound.Payload_Length_Mismatch =>
            raise Program_Error with "validated session message failed compound admission checks";
         when Compound.Local_Resource_Exhausted =>
            Result := Local_Resource_Exhausted;
         when Compound.Backpressure =>
            Result := Backpressure;
         when Compound.Send_Closed =>
            Result := Session_Closed;
         when Compound.Message_Accepted =>
            Result := Message_Accepted;
      end case;
   end Map_Result;

   protected body Received_Release_Gate is
      procedure Release
        (Value : in out Compound.Received_Message;
         Bound : in out Sessions.Binding)
      is
      begin
         Compound.Release (Value);
         Bound := Sessions.No_Binding;
      end Release;
   end Received_Release_Gate;

   protected body Session_Gate is
      procedure Try_Receive
        (Lane   : in out Compound.Lane;
         Bound  : Sessions.Binding;
         Target : in out Accepted_Message;
         Result : out Try_Take_Result)
      is
         Outcome : Compound.Try_Receive_Result;
      begin
         Target.Bound := Bound;
         begin
            Compound.Try_Receive (Lane, Target.Value, Outcome);
         exception
            when others =>
               if Compound.Is_Vacant (Target.Value) then
                  Target.Bound := Sessions.No_Binding;
               end if;
               raise;
         end;
         case Outcome is
            when Compound.Message_Received =>
               Result := Accepted_Message_Taken;
            when Compound.No_Message =>
               Target.Bound := Sessions.No_Binding;
               Result := No_Accepted_Message;
            when Compound.Receive_Closed =>
               Target.Bound := Sessions.No_Binding;
               Result := Ingress_Drained;
         end case;
      end Try_Receive;

      procedure Try_Forward
        (Lane     : in out Compound.Lane;
         Header   : Headers.Header;
         Payload  : in out Accepted_Message;
         Result   : out Try_Send_Result)
      is
         Outcome : Compound.Try_Send_Result;
      begin
         begin
            Compound.Try_Forward (Lane, Header, Payload.Value, Outcome);
         exception
            when others =>
               if Compound.Is_Vacant (Payload.Value) then
                  Payload.Bound := Sessions.No_Binding;
               end if;
               raise;
         end;
         if Outcome = Compound.Message_Accepted then
            Payload.Bound := Sessions.No_Binding;
         end if;
         Map_Result (Outcome, Result);
      end Try_Forward;

      procedure Close_And_Drain (Lane : in out Compound.Lane) is
         Target  : Compound.Received_Message (Lane.Payload_Storage, Lane.Header_Storage);
         Outcome : Compound.Try_Receive_Result;
      begin
         Compound.Close (Lane);
         loop
            Compound.Try_Receive (Lane, Target, Outcome);
            exit when Outcome /= Compound.Message_Received;
            Compound.Release (Target);
         end loop;
         if Outcome /= Compound.Receive_Closed then
            raise Program_Error with "closed session ingress did not drain exactly";
         end if;
      end Close_And_Drain;
   end Session_Gate;

   function Create
     (Bound           : Sessions.Binding;
      Payload_Storage : not null access Flyology.Buffers.Pool;
      Header_Storage  : not null access Flyology.Buffers.Pool) return Session
   is
   begin
      if not Sessions.Is_Valid (Bound) then
         raise Invalid_Session with "in-process session requires a valid exact binding";
      elsif Header_Storage.Block_Size < Natural (Headers.Encoded_Length) then
         raise Invalid_Configuration with "session header blocks are shorter than the V1 header";
      elsif Header_Storage.Capacity < Queue_Capacity
        or else Header_Storage.Capacity - Queue_Capacity < Maximum_Concurrent_Builders
      then
         raise Invalid_Configuration with "session header pool cannot cover queue and builder leases";
      end if;
      return Result : Session (Payload_Storage, Header_Storage) do
         Result.Bound := Bound;
      end return;
   end Create;

   function Session_Binding (Item : Session) return Sessions.Binding is
     (Item.Bound);

   procedure Acquire (Item : in out Writable_Payload) is
   begin
      Compound.Acquire (Item.Value);
   end Acquire;

   procedure Try_Acquire (Item : in out Writable_Payload; Acquired : out Boolean) is
   begin
      Compound.Try_Acquire (Item.Value, Acquired);
   end Try_Acquire;

   procedure Release (Item : in out Writable_Payload) is
   begin
      Compound.Release (Item.Value);
   end Release;

   procedure Release (Item : in out Accepted_Message) is
   begin
      Item.Release_Gate.Release (Item.Value, Item.Bound);
   end Release;

   function Has_Payload (Item : Writable_Payload) return Boolean is
     (Compound.Has_Payload (Item.Value));

   function Has_Message (Item : Accepted_Message) return Boolean is
     (Compound.Has_Message (Item.Value) and then Sessions.Is_Valid (Item.Bound));

   function Is_Vacant (Item : Accepted_Message) return Boolean is
     (Compound.Is_Vacant (Item.Value) and then not Sessions.Is_Valid (Item.Bound));

   function Length (Item : Writable_Payload) return Natural is
     (Compound.Length (Item.Value));

   function Length (Item : Accepted_Message) return Natural is
     (Compound.Length (Item.Value));

   function Payload_Capacity (Item : Writable_Payload) return Positive is
     (Compound.Payload_Capacity (Item.Value));

   procedure With_Writable_Data
     (Item    : in out Writable_Payload;
      Process :
        not null access procedure (Data : in out Ada.Streams.Stream_Element_Array; Length : in out Natural))
   is
   begin
      Compound.With_Writable_Data (Item.Value, Process);
   end With_Writable_Data;

   procedure With_Readable_Data
     (Item : Writable_Payload; Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   is
   begin
      Compound.With_Readable_Data (Item.Value, Process);
   end With_Readable_Data;

   procedure With_Readable_Data
     (Item : Accepted_Message; Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   is
   begin
      Compound.With_Readable_Data (Item.Value, Process);
   end With_Readable_Data;

   procedure With_Encoded_Header
     (Item : Accepted_Message; Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   is
   begin
      Compound.With_Encoded_Header (Item.Value, Process);
   end With_Encoded_Header;

   procedure Copy_From (Item : in out Writable_Payload; Data : Ada.Streams.Stream_Element_Array) is
   begin
      Compound.Copy_From (Item.Value, Data);
   end Copy_From;

   procedure Try_Send
     (Item        : in out Session;
      Source      : Endpoints.Endpoint_Reference;
      Destination : Endpoints.Endpoint_Reference;
      Message     : Messages.Message_ID;
      Correlation : Messages.Message_ID;
      Writer      : Flyology_Wire.Identities.Schema_Identity;
      Payload     : in out Writable_Payload;
      Result      : out Try_Send_Result)
   is
      Header  : Headers.Header;
      Outcome : Compound.Try_Send_Result;
   begin
      if Payload.Storage /= Item.Payload_Storage then
         raise Program_Error with "session payload belongs to another pool";
      elsif not Is_Valid_Message_Context (Message, Correlation, Writer) then
         Result := Invalid_Message_Context;
         return;
      elsif not Sessions.Is_Valid_Outbound_Route (Item.Bound, Source, Destination) then
         Result := Invalid_Outbound_Route;
         return;
      end if;
      Header :=
        Make_Outbound_Header
          (Source, Destination, Message, Correlation, Writer, Compound.Length (Payload.Value));
      if not Headers.Is_Valid (Header) then
         Result := Invalid_Message_Context;
         return;
      end if;
      Compound.Try_Send (Item.Ingress, Header, Payload.Value, Outcome);
      Map_Result (Outcome, Result);
   end Try_Send;

   procedure Try_Forward
     (Item        : in out Session;
      Source      : Endpoints.Endpoint_Reference;
      Destination : Endpoints.Endpoint_Reference;
      Message     : Messages.Message_ID;
      Correlation : Messages.Message_ID;
      Writer      : Flyology_Wire.Identities.Schema_Identity;
      Payload     : in out Accepted_Message;
      Result      : out Try_Send_Result)
   is
      Header : Headers.Header;
   begin
      if Payload.Payload_Storage /= Item.Payload_Storage then
         raise Program_Error with "forwarded session payload belongs to another pool";
      elsif not Is_Valid_Message_Context (Message, Correlation, Writer) then
         Result := Invalid_Message_Context;
         return;
      elsif not Sessions.Is_Valid_Outbound_Route (Item.Bound, Source, Destination) then
         Result := Invalid_Outbound_Route;
         return;
      end if;
      Header :=
        Make_Outbound_Header
          (Source, Destination, Message, Correlation, Writer, Compound.Length (Payload.Value));
      if not Headers.Is_Valid (Header) then
         Result := Invalid_Message_Context;
         return;
      end if;
      Item.Gate.Try_Forward (Item.Ingress, Header, Payload, Result);
   end Try_Forward;

   procedure Try_Take_Accepted
     (Item   : in out Session;
      Target : in out Accepted_Message;
      Result : out Try_Take_Result)
   is
   begin
      if Target.Payload_Storage /= Item.Payload_Storage
        or else Target.Header_Storage /= Item.Header_Storage
      then
         raise Program_Error with "session receive target belongs to another pool";
      elsif not Is_Vacant (Target) then
         raise Program_Error with "session receive target is occupied";
      end if;
      Item.Gate.Try_Receive (Item.Ingress, Item.Bound, Target, Result);
   end Try_Take_Accepted;

   function Session_Binding (Item : Accepted_Message) return Sessions.Binding is
     (Item.Bound);

   function Message (Item : Accepted_Message) return Messages.Message_ID is
     (Headers.Message (Compound.Envelope (Item.Value)));

   function Correlation (Item : Accepted_Message) return Messages.Message_ID is
     (Headers.Correlation (Compound.Envelope (Item.Value)));

   function Writer
     (Item : Accepted_Message) return Flyology_Wire.Identities.Schema_Identity
   is (Headers.Writer (Compound.Envelope (Item.Value)));

   function Source (Item : Accepted_Message) return Endpoints.Endpoint_Reference is
      Header : constant Headers.Header := Compound.Envelope (Item.Value);
   begin
      return
        Endpoints.Make_Endpoint_Reference
          (Sessions.Local_Node (Item.Bound),
           Headers.Source_Slot (Header),
           Headers.Source_Generation (Header));
   end Source;

   function Destination (Item : Accepted_Message) return Endpoints.Endpoint_Reference is
      Header : constant Headers.Header := Compound.Envelope (Item.Value);
   begin
      return
        Endpoints.Make_Endpoint_Reference
          (Sessions.Peer_Node (Item.Bound),
           Headers.Destination_Slot (Header),
           Headers.Destination_Generation (Header));
   end Destination;

   procedure Close (Item : in out Session) is
   begin
      Item.Gate.Close_And_Drain (Item.Ingress);
   end Close;

   function Current (Item : Session) return Transports.Lane_Snapshot is
     (Compound.Current (Item.Ingress));

   overriding procedure Finalize (Item : in out Session) is
   begin
      begin
         Close (Item);
      exception
         when others =>
            null;
      end;
   end Finalize;

end Flyology.Remoting.Sessions.In_Process;
