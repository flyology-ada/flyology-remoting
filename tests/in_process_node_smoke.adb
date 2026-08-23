with Ada.Streams;
with Flyology;
with Flyology.Buffers;
with Flyology.Remoting.Endpoints;
with Flyology.Remoting.Identities;
with Flyology.Remoting.Nodes;
with Flyology.Remoting.Nodes.In_Process;
with Remoting_Local_Node_Conformance;

procedure In_Process_Node_Smoke is
   package Buffers renames Flyology.Buffers;
   package Endpoints renames Flyology.Remoting.Endpoints;
   package Identities renames Flyology.Remoting.Identities;
   package Nodes renames Flyology.Remoting.Nodes;

   use type Ada.Streams.Stream_Element_Array;
   use type Buffers.Pool_Snapshot;
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

   procedure Run_Reusable_Conformance is
      Storage : aliased Buffers.Pool (Block_Size => 16, Capacity => 5);

      package Local is new
        Flyology.Remoting.Nodes.In_Process
          (Storage                                      => Storage'Access,
           Endpoint_Capacity                            => 1,
           Mailbox_Capacity                             => 2,
           Maximum_Concurrent_Operations_Per_Endpoint => 4);

      function Create_Writable return Local.Writable_Payload is
      begin
         return Result : Local.Writable_Payload do
            null;
         end return;
      end Create_Writable;

      function Create_Received return Local.Received_Payload is
      begin
         return Result : Local.Received_Payload do
            null;
         end return;
      end Create_Received;

      function Resources_Balanced return Boolean is
        (Buffers.Current (Storage) = (Available => 5, Outstanding => 0));

      package Conformance is new
        Remoting_Local_Node_Conformance
          (Endpoint_Capacity  => 1,
           Mailbox_Capacity   => 2,
           Local_Node         => Local.Node,
           Endpoint_Handle    => Local.Endpoint_Handle,
           Writable_Payload   => Local.Writable_Payload,
           Received_Payload   => Local.Received_Payload,
           Create_Node        => Local.Create,
           Node_Owner         => Local.Owner,
           Claim              => Local.Claim,
           Claim_Status       => Local.Status,
           Has_Endpoint       => Local.Has_Endpoint,
           Reference          => Local.Reference,
           Create_Writable    => Create_Writable,
           Create_Received    => Create_Received,
           Acquire            => Local.Payload_Transport.Acquire,
           Release_Received   => Local.Payload_Transport.Release,
           Has_Writable       => Local.Payload_Transport.Has_Payload,
           Has_Received       => Local.Payload_Transport.Has_Payload,
           Copy_From          => Local.Payload_Transport.Copy_From,
           Read_Writable      => Local.Payload_Transport.With_Readable_Data,
           Read_Received      => Local.Payload_Transport.With_Readable_Data,
           Try_Send_Writable  => Local.Try_Send,
           Try_Send_Received  => Local.Try_Send,
           Try_Receive        => Local.Try_Receive,
           Close              => Local.Close,
           Is_Current         => Local.Is_Current,
           Current            => Local.Current,
           Resources_Balanced => Resources_Balanced);
   begin
      Conformance.Run;
   end Run_Reusable_Conformance;

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
   Run_Reusable_Conformance;
   Run_Handle_Finalization;
   Run_Aborted_Handle;
   Run_Concurrent_Close;
end In_Process_Node_Smoke;
