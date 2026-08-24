with Ada.Streams;
with Flyology.Buffers;
with Flyology.Remoting.Endpoints;
with Flyology.Remoting.Compound_Testing;
with Flyology.Remoting.Messages;
with Flyology.Remoting.Protocol.V1.Headers;
with Flyology.Remoting.Transports;
with Flyology.Remoting.Transports.In_Process_Compound;
with Flyology_Wire;
with Flyology_Wire.Identities;

procedure In_Process_Compound_Transport_Smoke is
   package Buffers renames Flyology.Buffers;
   package Compound_Testing renames Flyology.Remoting.Compound_Testing;
   package Endpoints renames Flyology.Remoting.Endpoints;
   package Headers renames Flyology.Remoting.Protocol.V1.Headers;
   package Messages renames Flyology.Remoting.Messages;
   package Transports renames Flyology.Remoting.Transports;
   package Wire_Identities renames Flyology_Wire.Identities;

   package Reference is new
     Flyology.Remoting.Transports.In_Process_Compound
       (Queue_Capacity => 2, Maximum_Concurrent_Builders => 2);

   use type Buffers.Pool_Snapshot;
   use type Ada.Streams.Stream_Element_Array;
   use type Compound_Testing.Failure_Point;
   use type Headers.Decode_Status;
   use type Headers.Header;
   use type Reference.Try_Receive_Result;
   use type Reference.Try_Send_Result;
   use type Reference.Prepare_Result;
   use type Transports.Lane_Snapshot;

   subtype Commit_Failure_Point is Compound_Testing.Failure_Point range
     Compound_Testing.After_Header_Slot_Allocation .. Compound_Testing.After_Queue_Transfer;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Assert;

   Writer : constant Wire_Identities.Schema_Identity :=
     (Family      => [others => 1],
      Fingerprint => [others => 2],
      Revision    => Wire_Identities.Schema_Revision'First,
      Profile     => Wire_Identities.Profile_ID'First);

   function Make_Envelope (Payload_Length : Natural; Identity : Flyology_Wire.Octet) return Headers.Header is
     (Headers.Make_Header
        (Payload_Length          => Flyology_Wire.Byte_Count (Payload_Length),
         Message                 => Messages.Message_ID_From_Bytes ([others => Identity]),
         Correlation             => Messages.No_Message_ID,
         Source_Slot             => Endpoints.Slot_From_Word (1),
         Source_Generation       => Endpoints.Generation_From_Word (2),
         Destination_Slot        => Endpoints.Slot_From_Word (3),
         Destination_Generation  => Endpoints.Generation_From_Word (4),
         Writer                  => Writer));

   procedure Run_Compound_Ownership is
      Payload_Storage : aliased Buffers.Pool (Block_Size => 16, Capacity => 6);
      First_Headers   : aliased Buffers.Pool (Block_Size => 144, Capacity => 8);
      Second_Headers  : aliased Buffers.Pool (Block_Size => 144, Capacity => 6);
      First_Path      : Reference.Lane (Payload_Storage'Access, First_Headers'Access);
      Second_Path     : Reference.Lane (Payload_Storage'Access, Second_Headers'Access);
      First           : Reference.Writable_Payload (Payload_Storage'Access);
      Second          : Reference.Writable_Payload (Payload_Storage'Access);
      Overflow        : Reference.Writable_Payload (Payload_Storage'Access);
      Inbound         : Reference.Received_Message (Payload_Storage'Access, First_Headers'Access);
      Forwarded       : Reference.Received_Message (Payload_Storage'Access, Second_Headers'Access);
      Send_Result     : Reference.Try_Send_Result;
      Receive_Result  : Reference.Try_Receive_Result;
      procedure Check_Header (Data : Ada.Streams.Stream_Element_Array) is
         Decoded : Headers.Header;
         Status  : Headers.Decode_Status;
      begin
         Assert (Data'Length = 144, "received header lease did not retain the canonical extent");
         Headers.Decode (Data, Decoded, Status);
         Assert
           (Status = Headers.Header_Decoded and then Decoded = Reference.Envelope (Inbound),
            "received encoded and semantic headers diverged");
      end Check_Header;
   begin
      Reference.Acquire (First);
      Reference.Copy_From (First, [11, 12, 13]);
      Reference.Try_Send (First_Path, Make_Envelope (3, 1), First, Send_Result);
      Assert
        (Send_Result = Reference.Message_Accepted and then not Reference.Has_Payload (First),
         "accepted compound send retained caller payload ownership");

      Reference.Acquire (Second);
      Reference.Copy_From (Second, [21]);
      Reference.Try_Send (First_Path, Make_Envelope (1, 2), Second, Send_Result);
      Assert (Send_Result = Reference.Message_Accepted, "second compound send was not accepted");
      Assert
        (Reference.Current (First_Path) = (Closed => False, Pending => 2),
         "compound queue did not report its full state");
      Assert
        (Buffers.Current (First_Headers) = (Available => 6, Outstanding => 2),
         "accepted messages did not retain two header leases");

      Reference.Acquire (Overflow);
      Reference.Copy_From (Overflow, [31]);
      Reference.Try_Send (First_Path, Make_Envelope (1, 3), Overflow, Send_Result);
      Assert
        (Send_Result = Reference.Backpressure and then Reference.Has_Payload (Overflow),
         "compound backpressure consumed caller payload ownership");
      Assert
        (Buffers.Current (First_Headers) = (Available => 6, Outstanding => 2),
         "compound backpressure leaked its builder header");

      Reference.Try_Receive (First_Path, Inbound, Receive_Result);
      Assert
        (Receive_Result = Reference.Message_Received and then Reference.Has_Message (Inbound),
         "compound receive did not transfer both segments");
      Assert (Reference.Envelope (Inbound) = Make_Envelope (3, 1), "semantic header changed in queue");
      Reference.With_Encoded_Header (Inbound, Check_Header'Access);

      Reference.Try_Forward (Second_Path, Make_Envelope (3, 4), Inbound, Send_Result);
      Assert
        (Send_Result = Reference.Message_Accepted and then not Reference.Has_Message (Inbound),
         "accepted forwarding retained an old compound segment");
      Reference.Try_Receive (Second_Path, Forwarded, Receive_Result);
      Assert (Receive_Result = Reference.Message_Received, "forwarded compound was unavailable");
      Assert (Reference.Envelope (Forwarded) = Make_Envelope (3, 4), "forwarding did not re-envelope");
      Reference.Release (Forwarded);
      Assert
        (Buffers.Current (Second_Headers) = (Available => 6, Outstanding => 0),
         "cross-pool forwarding did not release its destination header lease");

      Reference.Try_Receive (First_Path, Inbound, Receive_Result);
      Assert (Receive_Result = Reference.Message_Received, "second queued compound was unavailable");
      Assert
        (Reference.Envelope (Inbound) = Make_Envelope (1, 2),
         "payload and header FIFO association crossed between entries");
      Reference.Close (Second_Path);
      Reference.Try_Forward (Second_Path, Make_Envelope (1, 5), Inbound, Send_Result);
      Assert
        (Send_Result = Reference.Send_Closed and then Reference.Has_Message (Inbound),
         "closed forwarding did not preserve both original segments");
      Reference.Release (Inbound);
      Reference.Try_Send (First_Path, Make_Envelope (1, 3), Overflow, Send_Result);
      Assert (Send_Result = Reference.Message_Accepted, "send after receive did not reuse header capacity");
      Reference.Close (First_Path);
      Reference.Try_Receive (First_Path, Inbound, Receive_Result);
      Assert (Receive_Result = Reference.Message_Received, "closed compound lane discarded accepted message");
      Reference.Release (Inbound);
      Reference.Try_Receive (First_Path, Inbound, Receive_Result);
      Assert (Receive_Result = Reference.Receive_Closed, "closed compound lane did not drain exactly");
      Assert
        (Buffers.Current (Payload_Storage) = (Available => 6, Outstanding => 0),
         "compound test leaked payload storage");
      Assert
        (Buffers.Current (First_Headers) = (Available => 8, Outstanding => 0),
         "compound test leaked source header storage");
      Assert
        (Buffers.Current (Second_Headers) = (Available => 6, Outstanding => 0),
         "compound test leaked destination header storage");
   end Run_Compound_Ownership;

   procedure Run_Zero_Copy_Forwarding is
      Payload_Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 1);
      First_Headers   : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
      Second_Headers  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
      First_Path      : Reference.Lane (Payload_Storage'Access, First_Headers'Access);
      Second_Path     : Reference.Lane (Payload_Storage'Access, Second_Headers'Access);
      Outbound        : Reference.Writable_Payload (Payload_Storage'Access);
      Probe           : Reference.Writable_Payload (Payload_Storage'Access);
      Inbound         : Reference.Received_Message (Payload_Storage'Access, First_Headers'Access);
      Forwarded       : Reference.Received_Message (Payload_Storage'Access, Second_Headers'Access);
      Acquired        : Boolean;
      Send_Result     : Reference.Try_Send_Result;
      Receive_Result  : Reference.Try_Receive_Result;
      procedure Check_Forwarded_Data (Data : Ada.Streams.Stream_Element_Array) is
      begin
         Assert (Data = [1, 2, 3], "forwarding changed opaque payload bytes");
      end Check_Forwarded_Data;
   begin
      Reference.Acquire (Outbound);
      Reference.Copy_From (Outbound, [1, 2, 3]);
      Reference.Try_Send (First_Path, Make_Envelope (3, 1), Outbound, Send_Result);
      Assert (Send_Result = Reference.Message_Accepted, "zero-copy setup send failed");
      Reference.Try_Acquire (Probe, Acquired);
      Assert (not Acquired, "send replaced the sole payload token");
      Reference.Try_Receive (First_Path, Inbound, Receive_Result);
      Assert (Receive_Result = Reference.Message_Received, "zero-copy setup receive failed");
      Reference.Try_Forward (Second_Path, Make_Envelope (3, 2), Inbound, Send_Result);
      Assert (Send_Result = Reference.Message_Accepted, "zero-copy forwarding was rejected");
      Reference.Try_Acquire (Probe, Acquired);
      Assert (not Acquired, "forwarding allocated or released the sole payload token");
      Reference.Try_Receive (Second_Path, Forwarded, Receive_Result);
      Assert (Receive_Result = Reference.Message_Received, "zero-copy forwarded receive failed");
      Reference.Try_Acquire (Probe, Acquired);
      Assert (not Acquired, "received forwarding did not retain the sole payload token");
      Reference.With_Readable_Data (Forwarded, Check_Forwarded_Data'Access);
      Reference.Release (Forwarded);
      Reference.Try_Acquire (Probe, Acquired);
      Assert (Acquired, "release did not return the sole payload token");
      Reference.Release (Probe);
   end Run_Zero_Copy_Forwarding;

   procedure Run_Validation_Precedence is
      Payload_Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 2);
      Header_Storage  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
      Path            : Reference.Lane (Payload_Storage'Access, Header_Storage'Access);
      Value           : Reference.Writable_Payload (Payload_Storage'Access);
      Result          : Reference.Try_Send_Result;
   begin
      Reference.Acquire (Value);
      Reference.Copy_From (Value, [1, 2]);
      Reference.Try_Send (Path, Headers.No_Header, Value, Result);
      Assert (Result = Reference.Invalid_Header, "invalid header did not precede length validation");
      Reference.Try_Send (Path, Make_Envelope (1, 1), Value, Result);
      Assert
        (Result = Reference.Payload_Length_Mismatch and then Reference.Has_Payload (Value),
         "payload-length failure consumed caller ownership");
      Assert
        (Buffers.Current (Header_Storage) = (Available => 4, Outstanding => 0),
         "validation allocated a header before completion");
      Reference.Release (Value);
   end Run_Validation_Precedence;

   procedure Run_Header_Exhaustion is
      Payload_Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 2);
      Header_Storage  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
      Path            : Reference.Lane (Payload_Storage'Access, Header_Storage'Access);
      Value           : Reference.Writable_Payload (Payload_Storage'Access);
      Hold_1          : Buffers.Unique_Buffer (Header_Storage'Access);
      Hold_2          : Buffers.Unique_Buffer (Header_Storage'Access);
      Hold_3          : Buffers.Unique_Buffer (Header_Storage'Access);
      Hold_4          : Buffers.Unique_Buffer (Header_Storage'Access);
      Result          : Reference.Try_Send_Result;
   begin
      Buffers.Acquire (Hold_1);
      Buffers.Acquire (Hold_2);
      Buffers.Acquire (Hold_3);
      Buffers.Acquire (Hold_4);
      Reference.Acquire (Value);
      Reference.Copy_From (Value, [9]);
      Reference.Try_Send (Path, Make_Envelope (1, 9), Value, Result);
      Assert
        (Result = Reference.Local_Resource_Exhausted and then Reference.Has_Payload (Value),
         "header exhaustion did not preserve caller payload ownership");
      Reference.Close (Path);
      Reference.Try_Send (Path, Make_Envelope (1, 9), Value, Result);
      Assert
        (Result = Reference.Send_Closed and then Reference.Has_Payload (Value),
         "closed lane did not precede exhausted header storage");
      Reference.Release (Value);
   end Run_Header_Exhaustion;

   procedure Run_Builder_Lifecycle is
      Payload_Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 6);
      Header_Storage  : aliased Buffers.Pool (Block_Size => 144, Capacity => 6);
      Path            : aliased Reference.Lane (Payload_Storage'Access, Header_Storage'Access);
      First_Builder   : Reference.Message_Builder (Path'Access);
      Second_Builder  : Reference.Message_Builder (Path'Access);
      Third_Builder   : Reference.Message_Builder (Path'Access);
      First           : Reference.Writable_Payload (Payload_Storage'Access);
      Second          : Reference.Writable_Payload (Payload_Storage'Access);
      Third           : Reference.Writable_Payload (Payload_Storage'Access);
      Inbound         : Reference.Received_Message (Payload_Storage'Access, Header_Storage'Access);
      Prepare_Status  : Reference.Prepare_Result;
      Send_Result     : Reference.Try_Send_Result;
      Receive_Result  : Reference.Try_Receive_Result;
   begin
      Reference.Prepare (First_Builder, Make_Envelope (1, 1), Prepare_Status);
      Assert (Prepare_Status = Reference.Builder_Prepared, "first builder was not prepared");
      Reference.Prepare (Second_Builder, Make_Envelope (1, 2), Prepare_Status);
      Assert (Prepare_Status = Reference.Builder_Prepared, "second builder was not prepared");
      Reference.Prepare (Third_Builder, Make_Envelope (1, 3), Prepare_Status);
      Assert
        (Prepare_Status = Reference.Prepare_Local_Resource_Exhausted
         and then not Reference.Is_Prepared (Third_Builder),
         "builder-capacity exhaustion was not deterministic");

      Reference.Reset (First_Builder);
      Assert (not Reference.Is_Prepared (First_Builder), "builder reset retained its reservation");
      Reference.Prepare (Third_Builder, Make_Envelope (1, 3), Prepare_Status);
      Assert (Prepare_Status = Reference.Builder_Prepared, "released builder slot was not reusable");

      Reference.Acquire (Second);
      Reference.Copy_From (Second, [2]);
      Reference.Try_Commit (Second_Builder, Second, Send_Result);
      Assert
        (Send_Result = Reference.Message_Accepted
         and then not Reference.Is_Prepared (Second_Builder)
         and then not Reference.Has_Payload (Second),
         "prepared builder commit did not transfer both leases");

      Reference.Acquire (First);
      Reference.Copy_From (First, [1]);
      Reference.Try_Send (Path, Make_Envelope (1, 1), First, Send_Result);
      Assert (Send_Result = Reference.Message_Accepted, "builder backpressure setup failed");

      Reference.Acquire (Third);
      Reference.Copy_From (Third, [3]);
      Reference.Try_Commit (Third_Builder, Third, Send_Result);
      Assert
        (Send_Result = Reference.Backpressure
         and then not Reference.Is_Prepared (Third_Builder)
         and then Reference.Has_Payload (Third),
         "backpressure did not release the builder while preserving payload");
      Reference.Prepare (Third_Builder, Make_Envelope (1, 3), Prepare_Status);
      Assert (Prepare_Status = Reference.Builder_Prepared, "backpressure builder was not reusable");
      Reference.Try_Receive (Path, Inbound, Receive_Result);
      Assert (Receive_Result = Reference.Message_Received, "builder retry receive setup failed");
      Reference.Release (Inbound);
      Reference.Try_Commit (Third_Builder, Third, Send_Result);
      Assert
        (Send_Result = Reference.Message_Accepted
         and then not Reference.Is_Prepared (Third_Builder)
         and then not Reference.Has_Payload (Third),
         "prepared builder retry did not commit exactly once");

      Reference.Prepare (First_Builder, Make_Envelope (1, 4), Prepare_Status);
      Assert (Prepare_Status = Reference.Builder_Prepared, "close-fence builder setup failed");
      Reference.Prepare (Second_Builder, Make_Envelope (1, 5), Prepare_Status);
      Assert (Prepare_Status = Reference.Builder_Prepared, "full builder-capacity setup failed");
      Assert
        (Buffers.Current (Header_Storage) = (Available => 2, Outstanding => 4),
         "full queue plus all builders did not retain exactly Q+B headers");
      Reference.Reset (Second_Builder);
      Reference.Acquire (First);
      Reference.Copy_From (First, [4, 5]);
      Reference.Try_Commit (First_Builder, First, Send_Result);
      Assert
        (Send_Result = Reference.Payload_Length_Mismatch
         and then not Reference.Is_Prepared (First_Builder)
         and then Reference.Has_Payload (First),
         "length mismatch did not release builder and preserve payload");
      Reference.Copy_From (First, [4]);
      Reference.Prepare (First_Builder, Make_Envelope (1, 4), Prepare_Status);
      Assert (Prepare_Status = Reference.Builder_Prepared, "close builder was not re-prepared");
      Reference.Close (Path);
      Reference.Try_Commit (First_Builder, First, Send_Result);
      Assert
        (Send_Result = Reference.Send_Closed
         and then not Reference.Is_Prepared (First_Builder)
         and then Reference.Has_Payload (First),
         "close did not release a prepared builder and preserve payload");
      Reference.Release (First);
      loop
         Reference.Try_Receive (Path, Inbound, Receive_Result);
         exit when Receive_Result = Reference.Receive_Closed;
         Assert
           (Receive_Result = Reference.Message_Received,
            "builder lane close returned an invalid result");
         Reference.Release (Inbound);
      end loop;
      Assert
        (Buffers.Current (Payload_Storage) = (Available => 6, Outstanding => 0),
         "builder lifecycle leaked payload ownership");
      Assert
        (Buffers.Current (Header_Storage) = (Available => 6, Outstanding => 0),
         "builder lifecycle leaked header ownership");
   end Run_Builder_Lifecycle;

   procedure Run_Abort_Cleanup is
      Payload_Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 3);
      Header_Storage  : aliased Buffers.Pool (Block_Size => 144, Capacity => 5);
      Path            : aliased Reference.Lane (Payload_Storage'Access, Header_Storage'Access);

      protected Builder_Signal is
         procedure Ready;
         entry Wait;
      private
         Is_Ready : Boolean := False;
      end Builder_Signal;

      protected body Builder_Signal is
         procedure Ready is
         begin
            Is_Ready := True;
         end Ready;

         entry Wait when Is_Ready is
         begin
            null;
         end Wait;
      end Builder_Signal;

      task Builder_Holder;

      task body Builder_Holder is
         Builder : Reference.Message_Builder (Path'Access);
         Status  : Reference.Prepare_Result;
      begin
         Reference.Prepare (Builder, Make_Envelope (1, 8), Status);
         if Status /= Reference.Builder_Prepared then
            raise Program_Error with "abort builder setup failed";
         end if;
         Builder_Signal.Ready;
         delay 3_600.0;
      end Builder_Holder;
   begin
      select
         Builder_Signal.Wait;
      or
         delay 5.0;
         raise Program_Error with "timed out waiting for prepared builder";
      end select;
      abort Builder_Holder;
      for Attempt in 1 .. 5_000 loop
         exit when Builder_Holder'Terminated;
         delay 0.001;
      end loop;
      Assert (Builder_Holder'Terminated, "prepared-builder abort did not terminate");
      Assert
        (Buffers.Current (Header_Storage) = (Available => 5, Outstanding => 0),
         "abandoned sealed builder did not release its header lease");
      declare
         Builder : Reference.Message_Builder (Path'Access);
         Status  : Reference.Prepare_Result;
      begin
         Reference.Prepare (Builder, Make_Envelope (1, 9), Status);
         Assert (Status = Reference.Builder_Prepared, "aborted builder reservation was not released");
      end;
      Assert
        (Buffers.Current (Header_Storage) = (Available => 5, Outstanding => 0),
         "replacement builder finalization leaked its header lease");
   end Run_Abort_Cleanup;

   procedure Run_Received_Abort_Cleanup is
      Payload_Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 2);
      Header_Storage  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
      Path            : aliased Reference.Lane (Payload_Storage'Access, Header_Storage'Access);
      Outbound        : Reference.Writable_Payload (Payload_Storage'Access);
      Send_Result     : Reference.Try_Send_Result;

      protected Receive_Signal is
         procedure Ready;
         entry Wait;
      private
         Is_Ready : Boolean := False;
      end Receive_Signal;

      protected body Receive_Signal is
         procedure Ready is
         begin
            Is_Ready := True;
         end Ready;

         entry Wait when Is_Ready is
         begin
            null;
         end Wait;
      end Receive_Signal;

      task Receiver is
         entry Start;
      end Receiver;

      task body Receiver is
         Inbound : Reference.Received_Message (Payload_Storage'Access, Header_Storage'Access);
         Result  : Reference.Try_Receive_Result;
      begin
         accept Start;
         Reference.Try_Receive (Path, Inbound, Result);
         if Result /= Reference.Message_Received then
            raise Program_Error with "abort receive setup failed";
         end if;
         Receive_Signal.Ready;
         delay 3_600.0;
      end Receiver;
   begin
      Reference.Acquire (Outbound);
      Reference.Copy_From (Outbound, [6]);
      Reference.Try_Send (Path, Make_Envelope (1, 6), Outbound, Send_Result);
      Assert (Send_Result = Reference.Message_Accepted, "abort receive message was not accepted");
      Receiver.Start;
      select
         Receive_Signal.Wait;
      or
         delay 5.0;
         raise Program_Error with "timed out waiting for received message";
      end select;
      abort Receiver;
      for Attempt in 1 .. 5_000 loop
         exit when Receiver'Terminated;
         delay 0.001;
      end loop;
      Assert (Receiver'Terminated, "received-message abort did not terminate");
      Assert
        (Buffers.Current (Payload_Storage) = (Available => 2, Outstanding => 0),
         "aborted receiver did not release its payload lease");
      Assert
        (Buffers.Current (Header_Storage) = (Available => 4, Outstanding => 0),
         "aborted receiver did not release its header lease");
   end Run_Received_Abort_Cleanup;

   procedure Run_Finalization_Drain is
      Payload_Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 2);
      Header_Storage  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
   begin
      declare
         Path   : Reference.Lane (Payload_Storage'Access, Header_Storage'Access);
         Value  : Reference.Writable_Payload (Payload_Storage'Access);
         Result : Reference.Try_Send_Result;
      begin
         Reference.Acquire (Value);
         Reference.Copy_From (Value, [7]);
         Reference.Try_Send (Path, Make_Envelope (1, 7), Value, Result);
         Assert (Result = Reference.Message_Accepted, "finalization-drain setup failed");
      end;
      Assert
        (Buffers.Current (Payload_Storage) = (Available => 2, Outstanding => 0),
         "lane finalization did not drain an accepted payload");
      Assert
        (Buffers.Current (Header_Storage) = (Available => 4, Outstanding => 0),
         "lane finalization did not drain its paired header");
   end Run_Finalization_Drain;

   procedure Run_Configuration_Check is
      Payload_Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 1);
      Short_Headers   : aliased Buffers.Pool (Block_Size => 143, Capacity => 4);
      Sparse_Headers  : aliased Buffers.Pool (Block_Size => 144, Capacity => 3);
      Short_Rejected  : Boolean := False;
      Sparse_Rejected : Boolean := False;
   begin
      begin
         declare
            Invalid : Reference.Lane (Payload_Storage'Access, Short_Headers'Access);
            pragma Unreferenced (Invalid);
         begin
            null;
         end;
      exception
         when Reference.Invalid_Configuration =>
            Short_Rejected := True;
      end;
      begin
         declare
            Invalid : Reference.Lane (Payload_Storage'Access, Sparse_Headers'Access);
            pragma Unreferenced (Invalid);
         begin
            null;
         end;
      exception
         when Reference.Invalid_Configuration =>
            Sparse_Rejected := True;
      end;
      Assert (Short_Rejected, "short canonical-header storage was accepted");
      Assert (Sparse_Rejected, "header pool smaller than queue plus builders was accepted");
   end Run_Configuration_Check;

   procedure Run_Injected_Commit_Failures is
      procedure Run_One (Point : Compound_Testing.Failure_Point) is
         Payload_Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 2);
         Header_Storage  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
         Path            : aliased Reference.Lane (Payload_Storage'Access, Header_Storage'Access);
         Builder         : Reference.Message_Builder (Path'Access);
         Value           : Reference.Writable_Payload (Payload_Storage'Access);
         Fill_1          : Reference.Writable_Payload (Payload_Storage'Access);
         Fill_2          : Reference.Writable_Payload (Payload_Storage'Access);
         Inbound         : Reference.Received_Message (Payload_Storage'Access, Header_Storage'Access);
         Prepare_Status  : Reference.Prepare_Result;
         Send_Result     : Reference.Try_Send_Result;
         Receive_Result  : Reference.Try_Receive_Result;
         Raised          : Boolean := False;
      begin
         Reference.Prepare (Builder, Make_Envelope (1, 11), Prepare_Status);
         Assert (Prepare_Status = Reference.Builder_Prepared, "fault-injection builder setup failed");
         Reference.Acquire (Value);
         Reference.Copy_From (Value, [11]);
         Compound_Testing.Arm (Point);
         begin
            Reference.Try_Commit (Builder, Value, Send_Result);
         exception
            when Program_Error =>
               Raised := True;
         end;
         Assert (Raised, "armed commit failure did not fire");
         Assert (not Reference.Is_Prepared (Builder), "failed commit retained its builder reservation");
         if Point = Compound_Testing.After_Queue_Transfer then
            Assert (not Reference.Has_Payload (Value), "accepted fault retained caller payload ownership");
            Assert
              (Reference.Current (Path) = (Closed => False, Pending => 1),
               "post-transfer fault lost its accepted queue entry");
            Reference.Try_Receive (Path, Inbound, Receive_Result);
            Assert (Receive_Result = Reference.Message_Received, "post-transfer fault was not drainable");
            Reference.Release (Inbound);
         else
            Assert (Reference.Has_Payload (Value), "pre-transfer fault consumed caller payload ownership");
            Assert
              (Reference.Current (Path) = (Closed => False, Pending => 0),
               "pre-transfer fault published a queue entry");
            Reference.Release (Value);
            Reference.Acquire (Fill_1);
            Reference.Copy_From (Fill_1, [14]);
            Reference.Try_Send (Path, Make_Envelope (1, 14), Fill_1, Send_Result);
            Assert (Send_Result = Reference.Message_Accepted, "first registry reuse failed");
            Reference.Acquire (Fill_2);
            Reference.Copy_From (Fill_2, [15]);
            Reference.Try_Send (Path, Make_Envelope (1, 15), Fill_2, Send_Result);
            Assert (Send_Result = Reference.Message_Accepted, "second registry reuse failed");
            for Position in 1 .. 2 loop
               Reference.Try_Receive (Path, Inbound, Receive_Result);
               Assert
                 (Receive_Result = Reference.Message_Received,
                  "registry reuse" & Position'Image & " was not drainable");
               Reference.Release (Inbound);
            end loop;
         end if;
         Assert
           (Buffers.Current (Payload_Storage) = (Available => 2, Outstanding => 0),
            "injected commit failure leaked payload storage");
         Assert
           (Buffers.Current (Header_Storage) = (Available => 4, Outstanding => 0),
            "injected commit failure leaked header storage");
         Compound_Testing.Reset;
      exception
         when others =>
            Compound_Testing.Reset;
            raise;
      end Run_One;
   begin
      for Point in Commit_Failure_Point loop
         Run_One (Point);
      end loop;
   end Run_Injected_Commit_Failures;

   procedure Run_Injected_Forward_Failures is
      procedure Run_One (Point : Compound_Testing.Failure_Point) is
         Payload_Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 2);
         Source_Headers  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
         Target_Headers  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
         Source          : Reference.Lane (Payload_Storage'Access, Source_Headers'Access);
         Target          : aliased Reference.Lane (Payload_Storage'Access, Target_Headers'Access);
         Builder         : Reference.Message_Builder (Target'Access);
         Outbound        : Reference.Writable_Payload (Payload_Storage'Access);
         Fill_1          : Reference.Writable_Payload (Payload_Storage'Access);
         Fill_2          : Reference.Writable_Payload (Payload_Storage'Access);
         Message         : Reference.Received_Message (Payload_Storage'Access, Source_Headers'Access);
         Forwarded       : Reference.Received_Message (Payload_Storage'Access, Target_Headers'Access);
         Prepare_Status  : Reference.Prepare_Result;
         Send_Result     : Reference.Try_Send_Result;
         Receive_Result  : Reference.Try_Receive_Result;
         Raised          : Boolean := False;
      begin
         Reference.Acquire (Outbound);
         Reference.Copy_From (Outbound, [12]);
         Reference.Try_Send (Source, Make_Envelope (1, 12), Outbound, Send_Result);
         Assert (Send_Result = Reference.Message_Accepted, "fault-injection forwarding setup failed");
         Reference.Try_Receive (Source, Message, Receive_Result);
         Assert (Receive_Result = Reference.Message_Received, "forwarding setup receive failed");
         Reference.Prepare (Builder, Make_Envelope (1, 13), Prepare_Status);
         Assert (Prepare_Status = Reference.Builder_Prepared, "forwarding builder setup failed");
         Compound_Testing.Arm (Point);
         begin
            Reference.Try_Commit_Forward (Builder, Message, Send_Result);
         exception
            when Program_Error =>
               Raised := True;
         end;
         Assert (Raised, "armed forwarding failure did not fire");
         Assert (not Reference.Is_Prepared (Builder), "failed forwarding retained its builder reservation");
         if Point = Compound_Testing.After_Queue_Transfer then
            Assert
              (not Reference.Has_Message (Message),
               "accepted forwarding fault retained source ownership");
            Assert
              (Reference.Current (Target) = (Closed => False, Pending => 1),
               "post-transfer forwarding fault lost its accepted pair");
            Reference.Try_Receive (Target, Forwarded, Receive_Result);
            Assert (Receive_Result = Reference.Message_Received, "forwarding fault was not drainable");
            Reference.Release (Forwarded);
         else
            Assert (Reference.Has_Message (Message), "pre-transfer forwarding fault consumed source message");
            Assert
              (Reference.Current (Target) = (Closed => False, Pending => 0),
               "pre-transfer forwarding fault published a queue entry");
            Reference.Release (Message);
            Reference.Acquire (Fill_1);
            Reference.Copy_From (Fill_1, [16]);
            Reference.Try_Send (Target, Make_Envelope (1, 16), Fill_1, Send_Result);
            Assert (Send_Result = Reference.Message_Accepted, "first forwarding registry reuse failed");
            Reference.Acquire (Fill_2);
            Reference.Copy_From (Fill_2, [17]);
            Reference.Try_Send (Target, Make_Envelope (1, 17), Fill_2, Send_Result);
            Assert (Send_Result = Reference.Message_Accepted, "second forwarding registry reuse failed");
            for Position in 1 .. 2 loop
               Reference.Try_Receive (Target, Forwarded, Receive_Result);
               Assert
                 (Receive_Result = Reference.Message_Received,
                  "forwarding registry reuse" & Position'Image & " was not drainable");
               Reference.Release (Forwarded);
            end loop;
         end if;
         Assert
           (Buffers.Current (Payload_Storage) = (Available => 2, Outstanding => 0),
            "injected forwarding failure leaked payload storage");
         Assert
           (Buffers.Current (Source_Headers) = (Available => 4, Outstanding => 0),
            "injected forwarding failure leaked source header storage");
         Assert
           (Buffers.Current (Target_Headers) = (Available => 4, Outstanding => 0),
            "injected forwarding failure leaked target header storage");
         Compound_Testing.Reset;
      exception
         when others =>
            Compound_Testing.Reset;
            raise;
      end Run_One;
   begin
      for Point in Commit_Failure_Point loop
         Run_One (Point);
      end loop;
   end Run_Injected_Forward_Failures;

   procedure Run_Injected_Prepare_Failure is
      Payload_Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 1);
      Header_Storage  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
      Path            : aliased Reference.Lane (Payload_Storage'Access, Header_Storage'Access);
      Builder         : Reference.Message_Builder (Path'Access);
      Status          : Reference.Prepare_Result;
      Raised          : Boolean := False;
   begin
      Compound_Testing.Arm (Compound_Testing.After_Builder_Reservation);
      begin
         Reference.Prepare (Builder, Make_Envelope (1, 20), Status);
      exception
         when Program_Error =>
            Raised := True;
      end;
      Assert (Raised, "armed prepare failure did not fire");
      Assert (not Reference.Is_Prepared (Builder), "failed prepare retained partial ownership");
      Assert
        (Buffers.Current (Header_Storage) = (Available => 4, Outstanding => 0),
         "failed prepare leaked its header lease");
      Reference.Prepare (Builder, Make_Envelope (1, 20), Status);
      Assert (Status = Reference.Builder_Prepared, "failed prepare leaked its builder reservation");
      Reference.Reset (Builder);
      Compound_Testing.Reset;
   exception
      when others =>
         Compound_Testing.Reset;
         raise;
   end Run_Injected_Prepare_Failure;

   procedure Run_Accepted_Send_Abort is
      Payload_Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 2);
      Header_Storage  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
      Path            : Reference.Lane (Payload_Storage'Access, Header_Storage'Access);

      protected Signal is
         procedure Accepted;
         entry Wait_Accepted;
      private
         Is_Accepted : Boolean := False;
      end Signal;

      protected body Signal is
         procedure Accepted is
         begin
            Is_Accepted := True;
         end Accepted;

         entry Wait_Accepted when Is_Accepted is
         begin
            null;
         end Wait_Accepted;
      end Signal;

      task Sender;

      task body Sender is
         Value  : Reference.Writable_Payload (Payload_Storage'Access);
         Result : Reference.Try_Send_Result;
      begin
         Reference.Acquire (Value);
         Reference.Copy_From (Value, [21]);
         Reference.Try_Send (Path, Make_Envelope (1, 21), Value, Result);
         if Result /= Reference.Message_Accepted then
            raise Program_Error with "accepted-send abort setup was rejected";
         end if;
         Signal.Accepted;
         delay 3_600.0;
      end Sender;

      Inbound        : Reference.Received_Message (Payload_Storage'Access, Header_Storage'Access);
      Receive_Result : Reference.Try_Receive_Result;
   begin
      select
         Signal.Wait_Accepted;
      or
         delay 5.0;
         raise Program_Error with "timed out waiting for accepted send";
      end select;
      abort Sender;
      for Attempt in 1 .. 5_000 loop
         exit when Sender'Terminated;
         delay 0.001;
      end loop;
      Assert (Sender'Terminated, "accepted sender abort did not terminate");
      Assert
        (Reference.Current (Path) = (Closed => False, Pending => 1),
         "caller abort removed an accepted message");
      Reference.Try_Receive (Path, Inbound, Receive_Result);
      Assert (Receive_Result = Reference.Message_Received, "accepted message was not drainable after abort");
      Reference.Release (Inbound);
      Assert
        (Buffers.Current (Payload_Storage) = (Available => 2, Outstanding => 0),
         "accepted-send abort leaked payload storage");
      Assert
        (Buffers.Current (Header_Storage) = (Available => 4, Outstanding => 0),
         "accepted-send abort leaked header storage");
   end Run_Accepted_Send_Abort;

   procedure Run_Accepted_Forward_Abort is
      Payload_Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 2);
      Source_Headers  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
      Target_Headers  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
      Source          : Reference.Lane (Payload_Storage'Access, Source_Headers'Access);
      Target          : Reference.Lane (Payload_Storage'Access, Target_Headers'Access);
      Outbound        : Reference.Writable_Payload (Payload_Storage'Access);
      Send_Result     : Reference.Try_Send_Result;

      protected Signal is
         procedure Accepted;
         entry Wait_Accepted;
      private
         Is_Accepted : Boolean := False;
      end Signal;

      protected body Signal is
         procedure Accepted is
         begin
            Is_Accepted := True;
         end Accepted;

         entry Wait_Accepted when Is_Accepted is
         begin
            null;
         end Wait_Accepted;
      end Signal;

      task Forwarder is
         entry Start;
      end Forwarder;

      task body Forwarder is
         Message        : Reference.Received_Message (Payload_Storage'Access, Source_Headers'Access);
         Receive_Result : Reference.Try_Receive_Result;
         Result         : Reference.Try_Send_Result;
      begin
         accept Start;
         Reference.Try_Receive (Source, Message, Receive_Result);
         if Receive_Result /= Reference.Message_Received then
            raise Program_Error with "accepted-forward abort receive failed";
         end if;
         Reference.Try_Forward (Target, Make_Envelope (1, 23), Message, Result);
         if Result /= Reference.Message_Accepted then
            raise Program_Error with "accepted-forward abort setup was rejected";
         end if;
         Signal.Accepted;
         delay 3_600.0;
      end Forwarder;

      Forwarded      : Reference.Received_Message (Payload_Storage'Access, Target_Headers'Access);
      Receive_Result : Reference.Try_Receive_Result;
   begin
      Reference.Acquire (Outbound);
      Reference.Copy_From (Outbound, [22]);
      Reference.Try_Send (Source, Make_Envelope (1, 22), Outbound, Send_Result);
      Assert (Send_Result = Reference.Message_Accepted, "accepted-forward abort source setup failed");
      Forwarder.Start;
      select
         Signal.Wait_Accepted;
      or
         delay 5.0;
         raise Program_Error with "timed out waiting for accepted forward";
      end select;
      abort Forwarder;
      for Attempt in 1 .. 5_000 loop
         exit when Forwarder'Terminated;
         delay 0.001;
      end loop;
      Assert (Forwarder'Terminated, "accepted forwarder abort did not terminate");
      Assert
        (Reference.Current (Target) = (Closed => False, Pending => 1),
         "caller abort removed an accepted forwarding");
      Reference.Try_Receive (Target, Forwarded, Receive_Result);
      Assert
        (Receive_Result = Reference.Message_Received,
         "accepted forwarding was not drainable after abort");
      Reference.Release (Forwarded);
      Assert
        (Buffers.Current (Payload_Storage) = (Available => 2, Outstanding => 0),
         "accepted-forward abort leaked payload storage");
      Assert
        (Buffers.Current (Source_Headers) = (Available => 4, Outstanding => 0),
         "accepted-forward abort leaked source headers");
      Assert
        (Buffers.Current (Target_Headers) = (Available => 4, Outstanding => 0),
         "accepted-forward abort leaked target headers");
   end Run_Accepted_Forward_Abort;

   procedure Run_Close_Commit_Race is
      procedure Run_One is
         Payload_Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 2);
         Header_Storage  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
         Path            : Reference.Lane (Payload_Storage'Access, Header_Storage'Access);

         protected Gate is
            procedure Arrive;
            entry Wait_All;
            entry Start;
            procedure Open;
         private
            Arrivals : Natural := 0;
            Is_Open  : Boolean := False;
         end Gate;

         protected body Gate is
            procedure Arrive is
            begin
               Arrivals := Arrivals + 1;
            end Arrive;

            entry Wait_All when Arrivals = 2 is
            begin
               null;
            end Wait_All;

            entry Start when Is_Open is
            begin
               null;
            end Start;

            procedure Open is
            begin
               Is_Open := True;
            end Open;
         end Gate;

         protected Outcome is
            procedure Set (Value : Reference.Try_Send_Result);
            function Get return Reference.Try_Send_Result;
         private
            Result : Reference.Try_Send_Result := Reference.Invalid_Header;
         end Outcome;

         protected body Outcome is
            procedure Set (Value : Reference.Try_Send_Result) is
            begin
               Result := Value;
            end Set;

            function Get return Reference.Try_Send_Result is (Result);
         end Outcome;

         task Sender;
         task Closer;

         task body Sender is
            Value  : Reference.Writable_Payload (Payload_Storage'Access);
            Result : Reference.Try_Send_Result;
         begin
            Reference.Acquire (Value);
            Reference.Copy_From (Value, [31]);
            Gate.Arrive;
            Gate.Start;
            Reference.Try_Send (Path, Make_Envelope (1, 31), Value, Result);
            Outcome.Set (Result);
         end Sender;

         task body Closer is
         begin
            Gate.Arrive;
            Gate.Start;
            Reference.Close (Path);
         end Closer;

         Inbound        : Reference.Received_Message (Payload_Storage'Access, Header_Storage'Access);
         Receive_Result : Reference.Try_Receive_Result;
         Snapshot       : Transports.Lane_Snapshot;
      begin
         select
            Gate.Wait_All;
         or
            delay 5.0;
            raise Program_Error with "timed out staging close/commit race";
         end select;
         Gate.Open;
         for Attempt in 1 .. 5_000 loop
            exit when Sender'Terminated and then Closer'Terminated;
            delay 0.001;
         end loop;
         Assert (Sender'Terminated and then Closer'Terminated, "close/commit race did not terminate");
         Assert
           (Outcome.Get = Reference.Message_Accepted or else Outcome.Get = Reference.Send_Closed,
            "close/commit race returned an invalid result");
         Snapshot := Reference.Current (Path);
         Assert (Snapshot.Closed, "close/commit race did not close the lane");
         if Outcome.Get = Reference.Message_Accepted then
            Assert (Snapshot.Pending = 1, "accepted close race did not retain its queue entry");
            Reference.Try_Receive (Path, Inbound, Receive_Result);
            Assert (Receive_Result = Reference.Message_Received, "accepted close race was not drainable");
            Reference.Release (Inbound);
         else
            Assert (Snapshot.Pending = 0, "rejected close race published a queue entry");
         end if;
         Reference.Try_Receive (Path, Inbound, Receive_Result);
         Assert (Receive_Result = Reference.Receive_Closed, "closed race lane did not drain exactly");
         Assert
           (Buffers.Current (Payload_Storage) = (Available => 2, Outstanding => 0),
            "close/commit race leaked payload storage");
         Assert
           (Buffers.Current (Header_Storage) = (Available => 4, Outstanding => 0),
            "close/commit race leaked header storage");
      end Run_One;
   begin
      for Attempt in 1 .. 50 loop
         Run_One;
      end loop;
   end Run_Close_Commit_Race;
begin
   Run_Compound_Ownership;
   Run_Zero_Copy_Forwarding;
   Run_Validation_Precedence;
   Run_Header_Exhaustion;
   Run_Builder_Lifecycle;
   Run_Abort_Cleanup;
   Run_Received_Abort_Cleanup;
   Run_Finalization_Drain;
   Run_Configuration_Check;
   Run_Injected_Commit_Failures;
   Run_Injected_Forward_Failures;
   Run_Injected_Prepare_Failure;
   Run_Accepted_Send_Abort;
   Run_Accepted_Forward_Abort;
   Run_Close_Commit_Race;
end In_Process_Compound_Transport_Smoke;
