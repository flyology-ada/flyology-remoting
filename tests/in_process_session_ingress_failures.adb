with Ada.Streams;
with Flyology.Buffers;
with Flyology.Remoting.Compound_Testing;
with Flyology.Remoting.Endpoints;
with Flyology.Remoting.Identities;
with Flyology.Remoting.Messages;
with Flyology.Remoting.Sessions;
with Flyology.Remoting.Sessions.In_Process;
with Flyology.Remoting.Transports;
with Flyology_Wire;
with Flyology_Wire.Identities;
with Remoting_Test_Codec;

procedure In_Process_Session_Ingress_Failures is
   package Buffers renames Flyology.Buffers;
   package Compound_Testing renames Flyology.Remoting.Compound_Testing;
   package Endpoints renames Flyology.Remoting.Endpoints;
   package Identities renames Flyology.Remoting.Identities;
   package Messages renames Flyology.Remoting.Messages;
   package Sessions renames Flyology.Remoting.Sessions;
   package Transports renames Flyology.Remoting.Transports;

   package Ingress is new
     Flyology.Remoting.Sessions.In_Process
       (Queue_Capacity => 2, Maximum_Concurrent_Builders => 1);

   use type Buffers.Pool_Snapshot;
   use type Ada.Streams.Stream_Element;
   use type Ingress.Try_Send_Result;
   use type Ingress.Try_Take_Result;
   use type Sessions.Binding;
   use type Transports.Lane_Snapshot;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Assert;

   Initiator_Node : constant Identities.Node_Reference :=
     Identities.Make_Node_Reference
       (Identities.Node_ID_From_Words (1, 2),
        Identities.Incarnation_ID_From_Words (3, 4));
   Acceptor_Node : constant Identities.Node_Reference :=
     Identities.Make_Node_Reference
       (Identities.Node_ID_From_Words (5, 6),
        Identities.Incarnation_ID_From_Words (7, 8));
   Session_Value : constant Identities.Session_Reference :=
     Identities.Make_Session_Reference
       (Initiator_Node, Acceptor_Node, Identities.Session_ID_From_Words (9, 10));
   Initiator_Binding : constant Sessions.Binding :=
     Sessions.Bind (Session_Value, Sessions.Initiator_Role);
   Acceptor_Binding : constant Sessions.Binding :=
     Sessions.Bind (Session_Value, Sessions.Acceptor_Role);
   Initiator_Endpoint : constant Endpoints.Endpoint_Reference :=
     Endpoints.Make_Endpoint_Reference
       (Initiator_Node, Endpoints.Slot_From_Word (1), Endpoints.Generation_From_Word (2));
   Acceptor_Endpoint : constant Endpoints.Endpoint_Reference :=
     Endpoints.Make_Endpoint_Reference
       (Acceptor_Node, Endpoints.Slot_From_Word (3), Endpoints.Generation_From_Word (4));
   Writer : constant Flyology_Wire.Identities.Schema_Identity :=
     Remoting_Test_Codec.Contract.Descriptor.Schema;

   function Message (Value : Flyology_Wire.Octet) return Messages.Message_ID is
     (Messages.Message_ID_From_Bytes ([others => Value]));

   procedure Send_One
     (Item     : in out Ingress.Session;
      Payload  : in out Ingress.Writable_Payload;
      Identity : Flyology_Wire.Octet;
      Result   : out Ingress.Try_Send_Result)
   is
   begin
      Ingress.Acquire (Payload);
      Ingress.Copy_From (Payload, [Identity]);
      Ingress.Try_Send
        (Item,
         Initiator_Endpoint,
         Acceptor_Endpoint,
         Message (Identity),
         Messages.No_Message_ID,
         Writer,
         Payload,
         Result);
   end Send_One;

   procedure Run_Close_Drain_And_Backpressure is
      Payloads : aliased Buffers.Pool (Block_Size => 8, Capacity => 3);
      Headers  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
      Item     : Ingress.Session := Ingress.Create (Initiator_Binding, Payloads'Access, Headers'Access);
      First    : Ingress.Writable_Payload (Payloads'Access);
      Second   : Ingress.Writable_Payload (Payloads'Access);
      Third    : Ingress.Writable_Payload (Payloads'Access);
      Target   : Ingress.Accepted_Message (Payloads'Access, Headers'Access);
      Send     : Ingress.Try_Send_Result;
      Take     : Ingress.Try_Take_Result;
   begin
      Send_One (Item, First, 1, Send);
      Assert (Send = Ingress.Message_Accepted, "first close-drain message was rejected");
      Send_One (Item, Second, 2, Send);
      Assert (Send = Ingress.Message_Accepted, "second close-drain message was rejected");
      Send_One (Item, Third, 3, Send);
      Assert
        (Send = Ingress.Backpressure and then Ingress.Has_Payload (Third),
         "session backpressure consumed the caller payload");
      Assert
        (Ingress.Current (Item) = (Closed => False, Pending => 2),
         "full session ingress reported the wrong state");
      Ingress.Close (Item);
      Assert
        (Ingress.Current (Item) = (Closed => True, Pending => 0),
         "session close did not synchronously drain accepted pairs");
      Ingress.Close (Item);
      Ingress.Try_Take_Accepted (Item, Target, Take);
      Assert (Take = Ingress.Ingress_Drained, "repeated close did not remain exactly drained");
      Ingress.Release (Third);
      Assert
        (Buffers.Current (Payloads) = (Available => 3, Outstanding => 0),
         "session close drain leaked payload storage");
      Assert
        (Buffers.Current (Headers) = (Available => 4, Outstanding => 0),
         "session close drain leaked header storage");
   end Run_Close_Drain_And_Backpressure;

   procedure Run_Local_Resource_Exhaustion is
      Payloads : aliased Buffers.Pool (Block_Size => 8, Capacity => 1);
      Headers  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
      Item     : Ingress.Session := Ingress.Create (Initiator_Binding, Payloads'Access, Headers'Access);
      Value    : Ingress.Writable_Payload (Payloads'Access);
      Hold_1   : Buffers.Unique_Buffer (Headers'Access);
      Hold_2   : Buffers.Unique_Buffer (Headers'Access);
      Hold_3   : Buffers.Unique_Buffer (Headers'Access);
      Hold_4   : Buffers.Unique_Buffer (Headers'Access);
      Result   : Ingress.Try_Send_Result;
   begin
      Buffers.Acquire (Hold_1);
      Buffers.Acquire (Hold_2);
      Buffers.Acquire (Hold_3);
      Buffers.Acquire (Hold_4);
      Send_One (Item, Value, 4, Result);
      Assert
        (Result = Ingress.Local_Resource_Exhausted and then Ingress.Has_Payload (Value),
         "session header exhaustion consumed the payload");
      Ingress.Release (Value);
      Buffers.Release (Hold_1);
      Buffers.Release (Hold_2);
      Buffers.Release (Hold_3);
      Buffers.Release (Hold_4);
      Ingress.Close (Item);
   end Run_Local_Resource_Exhaustion;

   procedure Run_Configuration_Checks is
      Payloads       : aliased Buffers.Pool (Block_Size => 8, Capacity => 1);
      Short_Headers  : aliased Buffers.Pool (Block_Size => 143, Capacity => 4);
      Sparse_Headers : aliased Buffers.Pool (Block_Size => 144, Capacity => 2);
      Valid_Headers  : aliased Buffers.Pool (Block_Size => 144, Capacity => 3);
      Short_Rejected : Boolean := False;
      Sparse_Rejected : Boolean := False;
      Binding_Rejected : Boolean := False;
   begin
      begin
         declare
            Invalid : Ingress.Session :=
              Ingress.Create (Initiator_Binding, Payloads'Access, Short_Headers'Access);
            pragma Unreferenced (Invalid);
         begin
            null;
         end;
      exception
         when Ingress.Invalid_Configuration =>
            Short_Rejected := True;
      end;
      begin
         declare
            Invalid : Ingress.Session :=
              Ingress.Create (Initiator_Binding, Payloads'Access, Sparse_Headers'Access);
            pragma Unreferenced (Invalid);
         begin
            null;
         end;
      exception
         when Ingress.Invalid_Configuration =>
            Sparse_Rejected := True;
      end;
      begin
         declare
            Invalid : Ingress.Session :=
              Ingress.Create (Sessions.No_Binding, Payloads'Access, Valid_Headers'Access);
            pragma Unreferenced (Invalid);
         begin
            null;
         end;
      exception
         when Sessions.Invalid_Session =>
            Binding_Rejected := True;
      end;
      Assert (Short_Rejected, "session accepted a short canonical-header block");
      Assert (Sparse_Rejected, "session accepted too few header leases");
      Assert (Binding_Rejected, "session accepted an invalid exact binding");
   end Run_Configuration_Checks;

   procedure Run_Pool_Provenance_Checks is
      Payloads       : aliased Buffers.Pool (Block_Size => 8, Capacity => 1);
      Other_Payloads : aliased Buffers.Pool (Block_Size => 8, Capacity => 1);
      Headers        : aliased Buffers.Pool (Block_Size => 144, Capacity => 3);
      Other_Headers  : aliased Buffers.Pool (Block_Size => 144, Capacity => 3);
      Item           : Ingress.Session :=
        Ingress.Create (Initiator_Binding, Payloads'Access, Headers'Access);
      Other_Item     : Ingress.Session :=
        Ingress.Create (Acceptor_Binding, Other_Payloads'Access, Other_Headers'Access);
      Foreign        : Ingress.Writable_Payload (Other_Payloads'Access);
      Local          : Ingress.Writable_Payload (Payloads'Access);
      Wrong_Payload_Target : Ingress.Accepted_Message (Other_Payloads'Access, Headers'Access);
      Wrong_Header_Target  : Ingress.Accepted_Message (Payloads'Access, Other_Headers'Access);
      Original       : Ingress.Accepted_Message (Payloads'Access, Headers'Access);
      Send_Result    : Ingress.Try_Send_Result;
      Take_Result    : Ingress.Try_Take_Result;
      Send_Rejected  : Boolean := False;
      Payload_Take_Rejected : Boolean := False;
      Header_Take_Rejected  : Boolean := False;
      Forward_Rejected : Boolean := False;
      Content_Preserved : Boolean := False;

      procedure Check_Original (Data : Ada.Streams.Stream_Element_Array) is
      begin
         Content_Preserved := Data'Length = 1 and then Data (Data'First) = 12;
      end Check_Original;
   begin
      Ingress.Acquire (Foreign);
      Ingress.Copy_From (Foreign, [11]);
      begin
         Ingress.Try_Send
           (Item,
            Initiator_Endpoint,
            Acceptor_Endpoint,
            Message (11),
            Messages.No_Message_ID,
            Writer,
            Foreign,
            Send_Result);
      exception
         when Program_Error =>
            Send_Rejected := True;
      end;
      Assert
        (Send_Rejected and then Ingress.Has_Payload (Foreign),
         "wrong-pool session send did not preserve caller ownership");
      begin
         Ingress.Try_Take_Accepted (Item, Wrong_Payload_Target, Take_Result);
      exception
         when Program_Error =>
            Payload_Take_Rejected := True;
      end;
      Assert
        (Payload_Take_Rejected and then Ingress.Is_Vacant (Wrong_Payload_Target),
         "wrong-payload session take changed its target");
      begin
         Ingress.Try_Take_Accepted (Item, Wrong_Header_Target, Take_Result);
      exception
         when Program_Error =>
            Header_Take_Rejected := True;
      end;
      Assert
        (Header_Take_Rejected and then Ingress.Is_Vacant (Wrong_Header_Target),
         "wrong-header session take changed its target");
      Ingress.Release (Foreign);

      Send_One (Item, Local, 12, Send_Result);
      Assert (Send_Result = Ingress.Message_Accepted, "wrong-pool forward setup send failed");
      Ingress.Try_Take_Accepted (Item, Original, Take_Result);
      Assert (Take_Result = Ingress.Accepted_Message_Taken, "wrong-pool forward setup take failed");
      begin
         Ingress.Try_Forward
           (Other_Item,
            Acceptor_Endpoint,
            Initiator_Endpoint,
            Message (13),
            Message (12),
            Writer,
            Original,
            Send_Result);
      exception
         when Program_Error =>
            Forward_Rejected := True;
      end;
      Ingress.With_Readable_Data (Original, Check_Original'Access);
      Assert
        (Forward_Rejected
         and then Ingress.Has_Message (Original)
         and then Ingress.Session_Binding (Original) = Initiator_Binding
         and then Content_Preserved,
         "wrong-payload forwarding changed the original message");
      Ingress.Release (Original);
      Ingress.Close (Item);
      Ingress.Close (Other_Item);
   end Run_Pool_Provenance_Checks;

   procedure Run_Forwarding_Faults is
      Payloads      : aliased Buffers.Pool (Block_Size => 8, Capacity => 2);
      Source_Headers : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
      Target_Headers : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
      Source         : Ingress.Session :=
        Ingress.Create (Initiator_Binding, Payloads'Access, Source_Headers'Access);
      Target         : Ingress.Session :=
        Ingress.Create (Acceptor_Binding, Payloads'Access, Target_Headers'Access);
      Outbound       : Ingress.Writable_Payload (Payloads'Access);
      Original       : Ingress.Accepted_Message (Payloads'Access, Source_Headers'Access);
      Forwarded      : Ingress.Accepted_Message (Payloads'Access, Target_Headers'Access);
      Send           : Ingress.Try_Send_Result;
      Take           : Ingress.Try_Take_Result;
      Raised         : Boolean := False;
   begin
      Send_One (Source, Outbound, 5, Send);
      Assert (Send = Ingress.Message_Accepted, "forward-fault source message was rejected");
      Ingress.Try_Take_Accepted (Source, Original, Take);
      Assert (Take = Ingress.Accepted_Message_Taken, "forward-fault source was unavailable");
      Compound_Testing.Arm (Compound_Testing.After_Queue_Transfer);
      begin
         Ingress.Try_Forward
           (Target,
            Acceptor_Endpoint,
            Initiator_Endpoint,
            Message (6),
            Message (5),
            Writer,
            Original,
            Send);
      exception
         when Program_Error =>
            Raised := True;
      end;
      Assert (Raised and then Ingress.Is_Vacant (Original), "postcommit forward retained stale binding");
      Assert
        (Ingress.Current (Target) = (Closed => False, Pending => 1),
         "postcommit forward fault lost its accepted descriptor");
      Ingress.Try_Take_Accepted (Target, Forwarded, Take);
      Assert (Take = Ingress.Accepted_Message_Taken, "faulted forwarding was not drainable");
      Assert (Ingress.Session_Binding (Forwarded) = Acceptor_Binding, "faulted forwarding rebound");
      Ingress.Release (Forwarded);
      Compound_Testing.Reset;
   exception
      when others =>
         Compound_Testing.Reset;
         raise;
   end Run_Forwarding_Faults;

   procedure Run_Rejected_Forward is
      Payloads      : aliased Buffers.Pool (Block_Size => 8, Capacity => 1);
      Source_Headers : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
      Target_Headers : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
      Source         : Ingress.Session :=
        Ingress.Create (Initiator_Binding, Payloads'Access, Source_Headers'Access);
      Target         : Ingress.Session :=
        Ingress.Create (Acceptor_Binding, Payloads'Access, Target_Headers'Access);
      Outbound       : Ingress.Writable_Payload (Payloads'Access);
      Original       : Ingress.Accepted_Message (Payloads'Access, Source_Headers'Access);
      Send           : Ingress.Try_Send_Result;
      Take           : Ingress.Try_Take_Result;
   begin
      Send_One (Source, Outbound, 7, Send);
      Assert (Send = Ingress.Message_Accepted, "rejected-forward source was rejected");
      Ingress.Try_Take_Accepted (Source, Original, Take);
      Assert (Take = Ingress.Accepted_Message_Taken, "rejected-forward source was unavailable");
      Ingress.Close (Target);
      Ingress.Try_Forward
        (Target,
         Acceptor_Endpoint,
         Initiator_Endpoint,
         Message (8),
         Message (7),
         Writer,
         Original,
         Send);
      Assert
        (Send = Ingress.Session_Closed
         and then Ingress.Has_Message (Original)
         and then Ingress.Session_Binding (Original) = Initiator_Binding,
         "rejected forwarding changed original ownership or binding");
      Ingress.Release (Original);
      Ingress.Close (Source);
   end Run_Rejected_Forward;

   procedure Run_Accepted_Send_Abort is
      Payloads : aliased Buffers.Pool (Block_Size => 8, Capacity => 2);
      Headers  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
      Item     : Ingress.Session := Ingress.Create (Initiator_Binding, Payloads'Access, Headers'Access);

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
         Payload : Ingress.Writable_Payload (Payloads'Access);
         Result  : Ingress.Try_Send_Result;
      begin
         Send_One (Item, Payload, 9, Result);
         if Result /= Ingress.Message_Accepted then
            raise Program_Error with "accepted session send abort setup was rejected";
         end if;
         Signal.Accepted;
         delay 3_600.0;
      end Sender;
   begin
      select
         Signal.Wait_Accepted;
      or
         delay 5.0;
         raise Program_Error with "timed out waiting for accepted session send";
      end select;
      abort Sender;
      for Attempt in 1 .. 5_000 loop
         exit when Sender'Terminated;
         delay 0.001;
      end loop;
      Assert (Sender'Terminated, "accepted session sender abort did not terminate");
      Assert
        (Ingress.Current (Item) = (Closed => False, Pending => 1),
         "caller abort removed an accepted session message");
      Ingress.Close (Item);
      Assert
        (Buffers.Current (Payloads) = (Available => 2, Outstanding => 0),
         "accepted session send abort leaked payload storage");
      Assert
        (Buffers.Current (Headers) = (Available => 4, Outstanding => 0),
         "accepted session send abort leaked header storage");
   end Run_Accepted_Send_Abort;

   procedure Run_Close_Send_Race is
      procedure Run_One is
         Payloads : aliased Buffers.Pool (Block_Size => 8, Capacity => 2);
         Headers  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
         Item     : Ingress.Session := Ingress.Create (Initiator_Binding, Payloads'Access, Headers'Access);

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
            procedure Set (Value : Ingress.Try_Send_Result);
            function Get return Ingress.Try_Send_Result;
         private
            Result : Ingress.Try_Send_Result := Ingress.Invalid_Message_Context;
         end Outcome;

         protected body Outcome is
            procedure Set (Value : Ingress.Try_Send_Result) is
            begin
               Result := Value;
            end Set;

            function Get return Ingress.Try_Send_Result is (Result);
         end Outcome;

         task Sender;
         task Closer;

         task body Sender is
            Payload : Ingress.Writable_Payload (Payloads'Access);
            Result  : Ingress.Try_Send_Result;
         begin
            Ingress.Acquire (Payload);
            Ingress.Copy_From (Payload, [10]);
            Gate.Arrive;
            Gate.Start;
            Ingress.Try_Send
              (Item,
               Initiator_Endpoint,
               Acceptor_Endpoint,
               Message (10),
               Messages.No_Message_ID,
               Writer,
               Payload,
               Result);
            Outcome.Set (Result);
         end Sender;

         task body Closer is
         begin
            Gate.Arrive;
            Gate.Start;
            Ingress.Close (Item);
         end Closer;
      begin
         select
            Gate.Wait_All;
         or
            delay 5.0;
            raise Program_Error with "timed out staging session close/send race";
         end select;
         Gate.Open;
         for Attempt in 1 .. 5_000 loop
            exit when Sender'Terminated and then Closer'Terminated;
            delay 0.001;
         end loop;
         Assert (Sender'Terminated and then Closer'Terminated, "session close/send race did not terminate");
         Assert
           (Outcome.Get = Ingress.Message_Accepted or else Outcome.Get = Ingress.Session_Closed,
            "session close/send race returned an invalid outcome");
         Assert
           (Ingress.Current (Item) = (Closed => True, Pending => 0),
            "session close/send race did not finish closed and drained");
         Assert
           (Buffers.Current (Payloads) = (Available => 2, Outstanding => 0),
            "session close/send race leaked payload storage");
         Assert
           (Buffers.Current (Headers) = (Available => 4, Outstanding => 0),
            "session close/send race leaked header storage");
      end Run_One;
   begin
      for Attempt in 1 .. 25 loop
         Run_One;
      end loop;
   end Run_Close_Send_Race;
begin
   Run_Close_Drain_And_Backpressure;
   Run_Local_Resource_Exhaustion;
   Run_Configuration_Checks;
   Run_Pool_Provenance_Checks;
   Run_Forwarding_Faults;
   Run_Rejected_Forward;
   Run_Accepted_Send_Abort;
   Run_Close_Send_Race;
end In_Process_Session_Ingress_Failures;
