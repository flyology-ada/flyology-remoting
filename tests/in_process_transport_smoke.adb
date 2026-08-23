with Ada.Streams;
with Flyology;
with Flyology.Buffers;
with Flyology.Remoting.Transports;
with Flyology.Remoting.Transports.In_Process;
with System;

procedure In_Process_Transport_Smoke is
   package Buffers renames Flyology.Buffers;
   package Transports renames Flyology.Remoting.Transports;

   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Offset;
   use type Buffers.Pool_Snapshot;
   use type Transports.Lane_Snapshot;
   use type Transports.Try_Receive_Result;
   use type Transports.Try_Send_Result;
   use type System.Address;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Assert;

   procedure Run_Ownership_And_Close is
      package Reference is new Flyology.Remoting.Transports.In_Process (Queue_Capacity => 1);

      Storage        : aliased Buffers.Pool (Block_Size => 16, Capacity => 4);
      Path           : Reference.Lane (Storage'Access);
      First          : Reference.Writable_Payload (Storage'Access);
      Second         : Reference.Writable_Payload (Storage'Access);
      After_Close    : Reference.Writable_Payload (Storage'Access);
      Target         : Reference.Received_Payload (Storage'Access);
      Send_Result    : Transports.Try_Send_Result;
      Receive_Result : Transports.Try_Receive_Result;

      procedure Check (Data : Ada.Streams.Stream_Element_Array) is
      begin
         Assert (Data = [1, 2, 3], "received payload changed");
      end Check;
   begin
      Reference.Acquire (First);
      Reference.Copy_From (First, [1, 2, 3]);
      Reference.Try_Send (Path, First, Send_Result);
      Assert
        (Send_Result = Transports.Message_Accepted and then not Reference.Has_Payload (First),
         "accepted send retained caller ownership");

      Reference.Acquire (Second);
      Reference.Copy_From (Second, [4, 5]);
      Reference.Try_Send (Path, Second, Send_Result);
      Assert
        (Send_Result = Transports.Backpressure and then Reference.Has_Payload (Second),
         "backpressure did not preserve caller ownership");

      Reference.Try_Receive (Path, Target, Receive_Result);
      Assert
        (Receive_Result = Transports.Message_Received and then Reference.Has_Payload (Target),
         "receive did not transfer ownership");
      Reference.With_Readable_Data (Target, Check'Access);
      Reference.Release (Target);

      Reference.Try_Send (Path, Second, Send_Result);
      Assert (Send_Result = Transports.Message_Accepted, "send after drain was not accepted");
      Reference.Close (Path);
      Assert (Reference.Current (Path) = (Closed => True, Pending => 1), "closed snapshot is wrong");

      Reference.Acquire (After_Close);
      Reference.Copy_From (After_Close, [9]);
      Reference.Try_Send (Path, After_Close, Send_Result);
      Assert
        (Send_Result = Transports.Send_Closed and then Reference.Has_Payload (After_Close),
         "closed send consumed caller ownership");

      Reference.Try_Receive (Path, Target, Receive_Result);
      Assert (Receive_Result = Transports.Message_Received, "close discarded an accepted payload");
      Reference.Release (Target);
      Reference.Try_Receive (Path, Target, Receive_Result);
      Assert (Receive_Result = Transports.Receive_Closed, "drained lane did not report closure");
      Reference.Release (After_Close);
      Assert
        (Buffers.Current (Storage) = (Available => 4, Outstanding => 0),
         "ownership accounting did not return to zero");
   end Run_Ownership_And_Close;

   procedure Run_FIFO is
      package Reference is new Flyology.Remoting.Transports.In_Process (Queue_Capacity => 4);

      Storage        : aliased Buffers.Pool (Block_Size => 4, Capacity => 5);
      Path           : Reference.Lane (Storage'Access);
      Outbound       : Reference.Writable_Payload (Storage'Access);
      Inbound        : Reference.Received_Payload (Storage'Access);
      Send_Result    : Transports.Try_Send_Result;
      Receive_Result : Transports.Try_Receive_Result;
   begin
      for Value in 1 .. 4 loop
         Reference.Acquire (Outbound);
         Reference.Copy_From (Outbound, [1 => Ada.Streams.Stream_Element (Value)]);
         Reference.Try_Send (Path, Outbound, Send_Result);
         Assert (Send_Result = Transports.Message_Accepted, "FIFO setup send failed");
      end loop;

      for Expected in 1 .. 4 loop
         declare
            Matches : Boolean := False;

            procedure Check (Data : Ada.Streams.Stream_Element_Array) is
            begin
               Matches := Data'Length = 1 and then Natural (Data (Data'First)) = Expected;
            end Check;
         begin
            Reference.Try_Receive (Path, Inbound, Receive_Result);
            Assert (Receive_Result = Transports.Message_Received, "FIFO receive failed");
            Reference.With_Readable_Data (Inbound, Check'Access);
            Assert (Matches, "accepted payloads were reordered");
            Reference.Release (Inbound);
         end;
      end loop;
   end Run_FIFO;

   procedure Run_Forwarding_And_Empty_Payload is
      package Reference is new Flyology.Remoting.Transports.In_Process (Queue_Capacity => 1);

      Storage        : aliased Buffers.Pool (Block_Size => 8, Capacity => 2);
      First_Path     : Reference.Lane (Storage'Access);
      Second_Path    : Reference.Lane (Storage'Access);
      Outbound       : Reference.Writable_Payload (Storage'Access);
      Relay          : Reference.Received_Payload (Storage'Access);
      Target         : Reference.Received_Payload (Storage'Access);
      Send_Result    : Transports.Try_Send_Result;
      Receive_Result : Transports.Try_Receive_Result;
      Before         : System.Address := System.Null_Address;
      After          : System.Address := System.Null_Address;

      procedure Remember_Before (Data : Ada.Streams.Stream_Element_Array) is
      begin
         Before := Data'Address;
      end Remember_Before;

      procedure Remember_After (Data : Ada.Streams.Stream_Element_Array) is
      begin
         After := Data'Address;
      end Remember_After;
   begin
      Reference.Acquire (Outbound);
      Assert (Reference.Length (Outbound) = 0, "new payload was not empty");
      Reference.Try_Send (First_Path, Outbound, Send_Result);
      Assert (Send_Result = Transports.Message_Accepted, "empty payload send failed");
      Reference.Try_Receive (First_Path, Relay, Receive_Result);
      Assert
        (Receive_Result = Transports.Message_Received and then Reference.Length (Relay) = 0,
         "empty payload did not survive transfer");
      Reference.Release (Relay);

      Reference.Acquire (Outbound);
      Reference.Copy_From (Outbound, [17, 18, 19]);
      Reference.With_Readable_Data (Outbound, Remember_Before'Access);
      Reference.Try_Send (First_Path, Outbound, Send_Result);
      Assert (Send_Result = Transports.Message_Accepted, "forward setup send failed");
      Reference.Try_Receive (First_Path, Relay, Receive_Result);
      Assert (Receive_Result = Transports.Message_Received, "forward setup receive failed");
      Reference.Try_Send (Second_Path, Relay, Send_Result);
      Assert
        (Send_Result = Transports.Message_Accepted and then not Reference.Has_Payload (Relay),
         "forward did not transfer receiver ownership");
      Reference.Try_Receive (Second_Path, Target, Receive_Result);
      Assert (Receive_Result = Transports.Message_Received, "forwarded payload was not received");
      Reference.With_Readable_Data (Target, Remember_After'Access);
      Assert (Before = After, "forwarding copied or replaced payload storage");
      Reference.Release (Target);
   end Run_Forwarding_And_Empty_Payload;

   procedure Run_Concurrent is
      package Reference is new Flyology.Remoting.Transports.In_Process (Queue_Capacity => 8);

      Iterations : constant Positive := 2_000;
      Storage    : aliased Buffers.Pool (Block_Size => 2, Capacity => 12);
      Path       : Reference.Lane (Storage'Access);

      protected Completion is
         procedure Producer_Finished (Success : Boolean);
         procedure Consumer_Finished (Success : Boolean; Count : Natural);
         entry Wait (Success : out Boolean; Count : out Natural);
      private
         Producer_Done : Boolean := False;
         Consumer_Done : Boolean := False;
         Producer_OK   : Boolean := False;
         Consumer_OK   : Boolean := False;
         Final_Count   : Natural := 0;
      end Completion;

      protected body Completion is
         procedure Producer_Finished (Success : Boolean) is
         begin
            Producer_OK := Success;
            Producer_Done := True;
         end Producer_Finished;

         procedure Consumer_Finished (Success : Boolean; Count : Natural) is
         begin
            Consumer_OK := Success;
            Final_Count := Count;
            Consumer_Done := True;
         end Consumer_Finished;

         entry Wait (Success : out Boolean; Count : out Natural)
           when Producer_Done and then Consumer_Done
         is
         begin
            Success := Producer_OK and then Consumer_OK;
            Count := Final_Count;
         end Wait;
      end Completion;

      task Producer is
         pragma Task_Info (Flyology.Lightweight_Task);
      end Producer;

      task Consumer is
         pragma Task_Info (Flyology.Lightweight_Task);
      end Consumer;

      task body Producer is
         Item   : Reference.Writable_Payload (Storage'Access);
         Result : Transports.Try_Send_Result;
      begin
         for Index in 1 .. Iterations loop
            Reference.Acquire (Item);
            Reference.Copy_From
              (Item,
               [Ada.Streams.Stream_Element (Index / 256), Ada.Streams.Stream_Element (Index mod 256)]);
            loop
               Reference.Try_Send (Path, Item, Result);
               exit when Result = Transports.Message_Accepted;
               if Result = Transports.Send_Closed then
                  raise Program_Error with "concurrent lane closed during send";
               end if;
               delay 0.0;
            end loop;
         end loop;
         Reference.Close (Path);
         Completion.Producer_Finished (True);
      exception
         when others =>
            Reference.Close (Path);
            Completion.Producer_Finished (False);
      end Producer;

      task body Consumer is
         Item     : Reference.Received_Payload (Storage'Access);
         Result   : Transports.Try_Receive_Result;
         Expected : Positive := 1;
         Valid    : Boolean := True;

         procedure Check (Data : Ada.Streams.Stream_Element_Array) is
            Value : Natural;
         begin
            if Data'Length /= 2 then
               Valid := False;
               return;
            end if;
            Value := Natural (Data (Data'First)) * 256 + Natural (Data (Data'First + 1));
            Valid := Valid and then Value = Expected;
         end Check;
      begin
         while Expected <= Iterations loop
            Reference.Try_Receive (Path, Item, Result);
            case Result is
               when Transports.Message_Received =>
                  Reference.With_Readable_Data (Item, Check'Access);
                  Reference.Release (Item);
                  Expected := Expected + 1;
               when Transports.No_Message =>
                  delay 0.0;
               when Transports.Receive_Closed =>
                  Valid := False;
                  exit;
            end case;
         end loop;
         Completion.Consumer_Finished (Valid, Expected - 1);
      exception
         when others =>
            Completion.Consumer_Finished (False, Expected - 1);
      end Consumer;

      Success : Boolean;
      Count   : Natural;
   begin
      Completion.Wait (Success, Count);
      Assert (Success and then Count = Iterations, "concurrent transfer lost, duplicated, or reordered data");
      Assert
        (Buffers.Current (Storage) = (Available => 12, Outstanding => 0),
         "concurrent transfer leaked payload ownership");
   end Run_Concurrent;

   procedure Run_Finalization_Cleanup is
      package Reference is new Flyology.Remoting.Transports.In_Process (Queue_Capacity => 1);

      Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 1);
   begin
      declare
         Path   : Reference.Lane (Storage'Access);
         Item   : Reference.Writable_Payload (Storage'Access);
         Result : Transports.Try_Send_Result;
      begin
         Reference.Acquire (Item);
         Reference.Copy_From (Item, [7]);
         Reference.Try_Send (Path, Item, Result);
         Assert (Result = Transports.Message_Accepted, "cleanup setup send failed");
      end;
      Assert
        (Buffers.Current (Storage) = (Available => 1, Outstanding => 0),
         "lane finalization did not release an undelivered payload");
   end Run_Finalization_Cleanup;
begin
   Run_Ownership_And_Close;
   Run_FIFO;
   Run_Forwarding_And_Empty_Payload;
   Run_Concurrent;
   Run_Finalization_Cleanup;
end In_Process_Transport_Smoke;
