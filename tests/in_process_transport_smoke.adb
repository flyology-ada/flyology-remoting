with Ada.Streams;
with Flyology;
with Flyology.Buffers;
with Flyology.Remoting.Transports;
with Flyology.Remoting.Transports.In_Process;
with Remoting_Payload_Lane_Conformance;
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

   procedure Run_Reusable_Conformance is
      package Reference is new Flyology.Remoting.Transports.In_Process (Queue_Capacity => 2);

      Storage : aliased Buffers.Pool (Block_Size => 16, Capacity => 6);

      subtype Lane is Reference.Lane (Storage'Access);
      subtype Writable_Payload is Reference.Writable_Payload (Storage'Access);
      subtype Received_Payload is Reference.Received_Payload (Storage'Access);

      function Create_Lane return Lane is
      begin
         return Result : Lane do
            null;
         end return;
      end Create_Lane;

      function Create_Writable return Writable_Payload is
      begin
         return Result : Writable_Payload do
            null;
         end return;
      end Create_Writable;

      function Create_Received return Received_Payload is
      begin
         return Result : Received_Payload do
            null;
         end return;
      end Create_Received;

      function Resources_Balanced return Boolean is
        (Buffers.Current (Storage) = (Available => 6, Outstanding => 0));

      package Conformance is new
        Remoting_Payload_Lane_Conformance
          (Lane               => Lane,
           Writable_Payload   => Writable_Payload,
           Received_Payload   => Received_Payload,
           Lane_Capacity      => 2,
           Create_Lane        => Create_Lane,
           Create_Writable    => Create_Writable,
           Create_Received    => Create_Received,
           Acquire            => Reference.Acquire,
           Release_Writable   => Reference.Release,
           Release_Received   => Reference.Release,
           Has_Writable       => Reference.Has_Payload,
           Has_Received       => Reference.Has_Payload,
           Length_Writable    => Reference.Length,
           Length_Received    => Reference.Length,
           Copy_From          => Reference.Copy_From,
           Read_Writable      => Reference.With_Readable_Data,
           Read_Received      => Reference.With_Readable_Data,
           Try_Send_Writable  => Reference.Try_Send,
           Try_Send_Received  => Reference.Try_Send,
           Try_Receive        => Reference.Try_Receive,
           Close              => Reference.Close,
           Current            => Reference.Current,
           Resources_Balanced => Resources_Balanced);
   begin
      Conformance.Run;
   end Run_Reusable_Conformance;

   procedure Run_Zero_Copy_Forwarding is
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
   end Run_Zero_Copy_Forwarding;

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
   Run_Reusable_Conformance;
   Run_Zero_Copy_Forwarding;
   Run_Concurrent;
   Run_Finalization_Cleanup;
end In_Process_Transport_Smoke;
