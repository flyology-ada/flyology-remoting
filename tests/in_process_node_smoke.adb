with Ada.Streams;
with Flyology;
with Flyology.Buffers;
with Flyology.Remoting.Endpoints;
with Flyology.Remoting.Identities;
with Flyology.Remoting.Nodes;
with Flyology.Remoting.Nodes.In_Process;

procedure In_Process_Node_Smoke is
   package Buffers renames Flyology.Buffers;
   package Endpoints renames Flyology.Remoting.Endpoints;
   package Identities renames Flyology.Remoting.Identities;
   package Nodes renames Flyology.Remoting.Nodes;

   use type Ada.Streams.Stream_Element_Array;
   use type Buffers.Pool_Snapshot;
   use type Endpoints.Endpoint_Generation;
   use type Endpoints.Endpoint_Slot;
   use type Identities.Node_Reference;
   use type Nodes.Claim_Result;
   use type Nodes.Close_Result;
   use type Nodes.Node_Snapshot;
   use type Nodes.Try_Receive_Result;
   use type Nodes.Try_Send_Result;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Assert;

   function Node_Identity
     (Node_High, Node_Low, Incarnation_High, Incarnation_Low : Identities.Identity_Word)
      return Identities.Node_Reference
   is
     (Identities.Make_Node_Reference
        (Identities.Node_ID_From_Words (Node_High, Node_Low),
         Identities.Incarnation_ID_From_Words (Incarnation_High, Incarnation_Low)));

   procedure Run_Routing_And_Reclaim is
      Storage : aliased Buffers.Pool (Block_Size => 16, Capacity => 5);

      package Local is new
        Flyology.Remoting.Nodes.In_Process
          (Storage                                      => Storage'Access,
           Endpoint_Capacity                            => 1,
           Mailbox_Capacity                             => 1,
           Maximum_Concurrent_Operations_Per_Endpoint => 4);

      Owner          : constant Identities.Node_Reference := Node_Identity (1, 2, 3, 4);
      Other_Node     : constant Identities.Node_Reference := Node_Identity (5, 6, 7, 8);
      Other_Lifetime : constant Identities.Node_Reference := Node_Identity (1, 2, 9, 10);
      Server         : aliased Local.Node := Local.Create (Owner);
      Endpoint_Owner : Local.Endpoint_Handle (Server'Access) := Local.Claim (Server'Access);
      Endpoint       : constant Endpoints.Endpoint_Reference := Local.Reference (Endpoint_Owner);
      Full_Owner     : constant Local.Endpoint_Handle (Server'Access) := Local.Claim (Server'Access);
      Foreign        : Endpoints.Endpoint_Reference;
      Old_Lifetime   : Endpoints.Endpoint_Reference;
      Outbound       : Local.Writable_Payload;
      Second         : Local.Writable_Payload;
      Inbound        : Local.Received_Payload;
      Send           : Nodes.Try_Send_Result;
      Receive_Result : Nodes.Try_Receive_Result;
      Closed         : Nodes.Close_Result;

      procedure Check (Data : Ada.Streams.Stream_Element_Array) is
      begin
         Assert (Data = [11, 12, 13], "node routing changed payload bytes");
      end Check;
   begin
      Assert (Local.Status (Endpoint_Owner) = Nodes.Endpoint_Claimed, "node did not claim its endpoint");
      Assert (Endpoints.Destination_Node (Endpoint) = Owner, "claimed endpoint has the wrong owner");
      Assert
        (Local.Status (Full_Owner) = Nodes.Directory_Full,
         "full node directory returned the wrong claim result");

      Local.Payload_Transport.Acquire (Outbound);
      Local.Payload_Transport.Copy_From (Outbound, [11, 12, 13]);
      Local.Try_Send (Server, Endpoint, Outbound, Send);
      Assert
        (Send = Nodes.Message_Accepted and then not Local.Payload_Transport.Has_Payload (Outbound),
         "node did not transfer accepted payload ownership");

      Local.Payload_Transport.Acquire (Second);
      Local.Payload_Transport.Copy_From (Second, [14]);
      Local.Try_Send (Server, Endpoint, Second, Send);
      Assert
        (Send = Nodes.Backpressure and then Local.Payload_Transport.Has_Payload (Second),
         "node backpressure consumed caller ownership");

      Local.Try_Receive (Server, Endpoint, Inbound, Receive_Result);
      Assert (Receive_Result = Nodes.Message_Received, "node did not receive an accepted payload");
      Local.Payload_Transport.With_Readable_Data (Inbound, Check'Access);
      Local.Payload_Transport.Release (Inbound);

      Foreign :=
        Endpoints.Make_Endpoint_Reference
          (Other_Node, Endpoints.Slot (Endpoint), Endpoints.Generation (Endpoint));
      Local.Try_Send (Server, Foreign, Second, Send);
      Assert (Send = Nodes.Foreign_Node, "node did not classify a foreign logical node");

      Old_Lifetime :=
        Endpoints.Make_Endpoint_Reference
          (Other_Lifetime, Endpoints.Slot (Endpoint), Endpoints.Generation (Endpoint));
      Local.Try_Send (Server, Old_Lifetime, Second, Send);
      Assert (Send = Nodes.Stale_Incarnation, "node did not classify a stale incarnation");

      Local.Try_Send (Server, Endpoint, Second, Send);
      Assert (Send = Nodes.Message_Accepted, "node did not refill the mailbox");
      Local.Close (Endpoint_Owner, Closed);
      Assert (Closed = Nodes.Endpoint_Closed, "node did not close its endpoint");
      Assert
        (not Local.Has_Endpoint (Endpoint_Owner)
         and then Local.Status (Endpoint_Owner) = Nodes.Endpoint_Claimed,
         "closed endpoint handle lost its original claim outcome");
      Assert
        (Local.Current (Server) = (Active => 0, Closing => 0, Available => 1, Exhausted => 0),
         "node close left incorrect directory accounting");
      Assert
        (Buffers.Current (Storage) = (Available => 5, Outstanding => 0),
         "node close did not drain accepted payload ownership");

      declare
         Replacement_Owner : Local.Endpoint_Handle (Server'Access) := Local.Claim (Server'Access);
         Replacement       : constant Endpoints.Endpoint_Reference := Local.Reference (Replacement_Owner);
      begin
         Assert
           (Local.Status (Replacement_Owner) = Nodes.Endpoint_Claimed,
            "node did not reclaim a retired slot");
         Assert
           (Endpoints.Slot (Replacement) = Endpoints.Slot (Endpoint),
            "node reclaimed another slot");
         Assert
           (Endpoints.Generation (Replacement) /= Endpoints.Generation (Endpoint),
            "node reuse did not advance the endpoint generation");

         Local.Payload_Transport.Acquire (Second);
         Local.Payload_Transport.Copy_From (Second, [15]);
         Local.Try_Send (Server, Endpoint, Second, Send);
         Assert
           (Send = Nodes.Stale_Endpoint and then Local.Payload_Transport.Has_Payload (Second),
            "stale endpoint send was accepted or consumed");
         Local.Payload_Transport.Release (Second);
         Local.Close (Replacement_Owner, Closed);
         Assert (Closed = Nodes.Endpoint_Closed, "replacement endpoint did not close");
      end;
   end Run_Routing_And_Reclaim;

   procedure Run_Handle_Finalization is
      Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 2);

      package Local is new
        Flyology.Remoting.Nodes.In_Process
          (Storage                                      => Storage'Access,
           Endpoint_Capacity                            => 1,
           Mailbox_Capacity                             => 1,
           Maximum_Concurrent_Operations_Per_Endpoint => 2);

      Owner  : constant Identities.Node_Reference := Node_Identity (40, 41, 42, 43);
      Server : aliased Local.Node := Local.Create (Owner);
   begin
      declare
         Endpoint_Owner : constant Local.Endpoint_Handle (Server'Access) := Local.Claim (Server'Access);
         Endpoint       : constant Endpoints.Endpoint_Reference := Local.Reference (Endpoint_Owner);
         Payload        : Local.Writable_Payload;
         Result         : Nodes.Try_Send_Result;
      begin
         Local.Payload_Transport.Acquire (Payload);
         Local.Payload_Transport.Copy_From (Payload, [91]);
         Local.Try_Send (Server, Endpoint, Payload, Result);
         Assert (Result = Nodes.Message_Accepted, "finalization setup send failed");
      end;

      Assert
        (Local.Current (Server) = (Active => 0, Closing => 0, Available => 1, Exhausted => 0),
         "endpoint handle finalization did not retire its claim");
      Assert
        (Buffers.Current (Storage) = (Available => 2, Outstanding => 0),
         "endpoint handle finalization did not drain its mailbox");
   end Run_Handle_Finalization;

   procedure Run_Aborted_Handle is
      Storage : aliased Buffers.Pool (Block_Size => 8, Capacity => 2);

      package Local is new
        Flyology.Remoting.Nodes.In_Process
          (Storage                                      => Storage'Access,
           Endpoint_Capacity                            => 1,
           Mailbox_Capacity                             => 1,
           Maximum_Concurrent_Operations_Per_Endpoint => 2);

      Owner  : constant Identities.Node_Reference := Node_Identity (50, 51, 52, 53);
      Server : aliased Local.Node := Local.Create (Owner);

      protected Gate is
         procedure Mark_Ready;
         entry Wait_Ready;
         entry Hold;
      private
         Ready : Boolean := False;
      end Gate;

      protected body Gate is
         procedure Mark_Ready is
         begin
            Ready := True;
         end Mark_Ready;

         entry Wait_Ready when Ready is
         begin
            null;
         end Wait_Ready;

         entry Hold when False is
         begin
            null;
         end Hold;
      end Gate;

      task Endpoint_Task is
         pragma Task_Info (Flyology.Lightweight_Task);
      end Endpoint_Task;

      task body Endpoint_Task is
         Endpoint_Owner : constant Local.Endpoint_Handle (Server'Access) := Local.Claim (Server'Access);
         Endpoint       : constant Endpoints.Endpoint_Reference := Local.Reference (Endpoint_Owner);
         Payload        : Local.Writable_Payload;
         Result         : Nodes.Try_Send_Result;
      begin
         Local.Payload_Transport.Acquire (Payload);
         Local.Payload_Transport.Copy_From (Payload, [92]);
         Local.Try_Send (Server, Endpoint, Payload, Result);
         Assert (Result = Nodes.Message_Accepted, "abort setup send failed");
         Gate.Mark_Ready;
         Gate.Hold;
      end Endpoint_Task;
   begin
      Gate.Wait_Ready;
      abort Endpoint_Task;
      while not Endpoint_Task'Terminated loop
         delay 0.0;
      end loop;

      Assert
        (Local.Current (Server) = (Active => 0, Closing => 0, Available => 1, Exhausted => 0),
         "aborted endpoint owner did not retire its claim");
      Assert
        (Buffers.Current (Storage) = (Available => 2, Outstanding => 0),
         "aborted endpoint owner did not drain its mailbox");
   end Run_Aborted_Handle;

   procedure Run_Concurrent_Close is
      Storage : aliased Buffers.Pool (Block_Size => 4, Capacity => 12);

      package Local is new
        Flyology.Remoting.Nodes.In_Process
          (Storage                                      => Storage'Access,
           Endpoint_Capacity                            => 1,
           Mailbox_Capacity                             => 8,
           Maximum_Concurrent_Operations_Per_Endpoint => 2);

      Owner    : constant Identities.Node_Reference := Node_Identity (20, 21, 22, 23);
      Server         : aliased Local.Node := Local.Create (Owner);
      Endpoint_Owner : Local.Endpoint_Handle (Server'Access) := Local.Claim (Server'Access);
      Endpoint       : constant Endpoints.Endpoint_Reference := Local.Reference (Endpoint_Owner);

      protected Progress is
         procedure Start;
         entry Await_Start;
         procedure Started;
         entry Wait_Started;
         procedure Finished (Success : Boolean);
         entry Wait_Finished (Success : out Boolean);
      private
         Can_Start   : Boolean := False;
         Has_Started : Boolean := False;
         Is_Done     : Boolean := False;
         Was_OK      : Boolean := False;
      end Progress;

      protected body Progress is
         procedure Start is
         begin
            Can_Start := True;
         end Start;

         entry Await_Start when Can_Start is
         begin
            null;
         end Await_Start;

         procedure Started is
         begin
            Has_Started := True;
         end Started;

         entry Wait_Started when Has_Started is
         begin
            null;
         end Wait_Started;

         procedure Finished (Success : Boolean) is
         begin
            Was_OK := Success;
            Is_Done := True;
         end Finished;

         entry Wait_Finished (Success : out Boolean) when Is_Done is
         begin
            Success := Was_OK;
         end Wait_Finished;
      end Progress;

      task Producer is
         pragma Task_Info (Flyology.Lightweight_Task);
      end Producer;

      task body Producer is
         Payload : Local.Writable_Payload;
         Result  : Nodes.Try_Send_Result;
         Success : Boolean := True;
         Stopped : Boolean := False;
         First   : Boolean := True;
      begin
         Progress.Await_Start;
         Producer_Loop : for Value in 1 .. 2_000 loop
            Local.Payload_Transport.Acquire (Payload);
            Local.Payload_Transport.Copy_From
              (Payload, [1 => Ada.Streams.Stream_Element (Value mod 256)]);
            loop
               Local.Try_Send (Server, Endpoint, Payload, Result);
               if Result = Nodes.Message_Accepted then
                  if First then
                     Progress.Started;
                     First := False;
                  end if;
                  exit;
               end if;
               if Result = Nodes.Endpoint_Closing or else Result = Nodes.Stale_Endpoint then
                  Local.Payload_Transport.Release (Payload);
                  Stopped := True;
                  exit Producer_Loop;
               elsif Result /= Nodes.Backpressure and then Result /= Nodes.Local_Resource_Exhausted then
                  Success := False;
                  Local.Payload_Transport.Release (Payload);
                  Stopped := True;
                  exit Producer_Loop;
               end if;
               delay 0.0;
            end loop;
         end loop Producer_Loop;
         Progress.Finished (Success and then Stopped);
      exception
         when others =>
            if Local.Payload_Transport.Has_Payload (Payload) then
               Local.Payload_Transport.Release (Payload);
            end if;
            Progress.Finished (False);
      end Producer;

      Closed  : Nodes.Close_Result;
      Success : Boolean;
   begin
      Assert
        (Local.Status (Endpoint_Owner) = Nodes.Endpoint_Claimed,
         "concurrent close setup claim failed");
      Progress.Start;
      Progress.Wait_Started;
      delay 0.0;
      Local.Close (Endpoint_Owner, Closed);
      Progress.Wait_Finished (Success);
      Assert (Closed = Nodes.Endpoint_Closed and then Success, "concurrent close did not converge");
      Assert
        (Buffers.Current (Storage) = (Available => 12, Outstanding => 0),
         "concurrent close leaked payload ownership");
   end Run_Concurrent_Close;
begin
   Run_Routing_And_Reclaim;
   Run_Handle_Finalization;
   Run_Aborted_Handle;
   Run_Concurrent_Close;
end In_Process_Node_Smoke;
