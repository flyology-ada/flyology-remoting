with Ada.Real_Time;
with Flyology;
with Flyology.Execution_Groups;
with Flyology.Remoting.Identities;
with Flyology.Remoting.Tasks;
with Flyology.Remoting.Tasks.From_Supervision;
with Flyology.Remoting.Tasks.Local_Observers;
with Flyology.Supervision;

procedure Task_Lifecycle_Smoke is
   package Identities renames Flyology.Remoting.Identities;
   package Tasks renames Flyology.Remoting.Tasks;
   package Conversion renames Flyology.Remoting.Tasks.From_Supervision;
   package Supervision renames Flyology.Supervision;

   use type Identities.Node_Reference;
   use type Supervision.Child_State;
   use type Tasks.Completion_Kind;
   use type Tasks.Observation_Status;
   use type Tasks.Task_Generation;
   use type Tasks.Task_ID;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Assert;

   procedure Assert_Status
     (Item : Tasks.Task_Observation; Expected : Tasks.Observation_Status; Message : String)
   is
   begin
      Assert (Item.Status = Expected, Message);
   end Assert_Status;

   Node : constant Identities.Node_Reference :=
     Identities.Make_Node_Reference
       (Identities.Node_ID_From_Words (31, 32), Identities.Incarnation_ID_From_Words (33, 34));

   Reference : constant Tasks.Task_Reference :=
     Tasks.Make_Task_Reference (Node, Tasks.Task_ID_From_Word (701), Tasks.Generation_From_Word (9));

   Termination : Supervision.Termination_Summary;

   function Snapshot
     (Generation : Supervision.Generation; State : Supervision.Child_State)
      return Supervision.Child_Snapshot
   is
     ((Id          => 7,
       Generation  => Generation,
       State       => State,
       Task_Model  => Flyology.Lightweight_Task,
       Has_Group   => False,
       Group       => Flyology.Execution_Groups.Group_Id'First,
       Termination => Termination,
       Attempts    => 0,
       Backoff     => Ada.Real_Time.Time_Span_Zero,
       Ready       => State = Supervision.Running,
       Live        => State = Supervision.Running,
       Escalated   => False));

   procedure Run_Local_Observer is
      type Local_Handle is record
         Generation : Supervision.Generation;
      end record;

      type Local_Supervisor is record
         Next_Status     : Supervision.Generation_Observation_Status := Supervision.Observation_Timed_Out;
         Next_Generation : Supervision.Generation := Supervision.Generation'First;
         Calls           : Natural := 0;
      end record;

      function Handle_Generation (Handle : Local_Handle) return Supervision.Generation is
        (Handle.Generation);

      function Wait_Termination
        (Item    : in out Local_Supervisor;
         Handle  : Local_Handle;
         Timeout : Duration) return Supervision.Generation_Observation
      is
         pragma Unreferenced (Handle, Timeout);
      begin
         Item.Calls := Item.Calls + 1;
         case Item.Next_Status is
            when Supervision.Observation_Timed_Out =>
               return (Status => Supervision.Observation_Timed_Out);
            when Supervision.Generation_Terminated =>
               return
                 (Status   => Supervision.Generation_Terminated,
                  Snapshot => Snapshot (Item.Next_Generation, Supervision.Terminated));
            when Supervision.Generation_Replaced =>
               return
                 (Status   => Supervision.Generation_Replaced,
                  Snapshot => Snapshot (Item.Next_Generation, Supervision.Running));
         end case;
      end Wait_Termination;

      package Observer is new
        Tasks.Local_Observers
          (Local_Supervisor  => Local_Supervisor,
           Local_Handle      => Local_Handle,
           Handle_Generation => Handle_Generation,
           Wait_Termination  => Wait_Termination);

      Provider : Local_Supervisor;
      Handle   : constant Local_Handle := (Generation => 9);
   begin
      declare
         Result : constant Tasks.Task_Observation :=
           Observer.Observe_Exact (Provider, Handle, Reference, Timeout => 0.0);
      begin
         Assert (Result.Status = Tasks.Observation_Timed_Out, "local observer changed timeout status");
         Assert (Provider.Calls = 1, "local observer did not call the exact wait once");
      end;

      Provider.Next_Status := Supervision.Generation_Replaced;
      Provider.Next_Generation := 10;
      declare
         Result : constant Tasks.Task_Observation :=
           Observer.Observe_Exact (Provider, Handle, Reference, Timeout => 0.0);
      begin
         Assert (Result.Status = Tasks.Task_Replaced, "local observer lost replacement status");
         Assert
           (Tasks.Identity (Result.Replacement) = Tasks.Identity (Reference),
            "local observer changed the node-global task identity");
      end;

      Provider.Next_Status := Supervision.Generation_Terminated;
      Provider.Next_Generation := 9;
      declare
         Result : constant Tasks.Task_Observation :=
           Observer.Observe_Exact (Provider, Handle, Reference, Timeout => 0.0);
      begin
         Assert (Result.Status = Tasks.Task_Ended, "local observer lost terminal status");
         Assert
           (Result.Completion.Kind = Tasks.Unhandled_Exception,
            "local observer changed the terminal completion");
      end;

      Provider.Calls := 0;
      declare
         Rejected : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Tasks.Task_Observation :=
                 Observer.Observe_Exact
                   (Provider, (Generation => 8), Reference, Timeout => 0.0);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Program_Error =>
               Rejected := True;
         end;
         Assert (Rejected, "local observer accepted a mismatched supervisor generation");
         Assert (Provider.Calls = 0, "local observer waited before rejecting a mismatched handle");

         Rejected := False;
         begin
            declare
               Ignored : constant Tasks.Task_Observation :=
                 Observer.Observe_Exact (Provider, Handle, Tasks.No_Task, Timeout => 0.0);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Program_Error =>
               Rejected := True;
         end;
         Assert (Rejected, "local observer accepted an invalid remoting reference");
         Assert (Provider.Calls = 0, "local observer waited before rejecting an invalid reference");
      end;
   end Run_Local_Observer;

begin
   Assert (Tasks.Is_Valid (Reference), "valid remote task reference was rejected");
   Assert (Tasks.Destination_Node (Reference) = Node, "remote task node identity changed");
   Assert (Tasks.Identity (Reference) = Tasks.Task_ID_From_Word (701), "remote task identity changed");
   Assert
     (Tasks.Generation (Reference) = Tasks.Generation_From_Word (9),
      "remote task generation changed");
   Assert (not Tasks.Is_Valid (Tasks.No_Task), "invalid remote task sentinel was accepted");

   Termination.Kind := Supervision.Unhandled_Exception;
   Termination.Exception_Name_Length := 12;
   Termination.Exception_Name (1 .. 12) := "TEST_FAILURE";
   Termination.Message_Length := 4;
   Termination.Message (1 .. 4) := "boom";

   Run_Local_Observer;

   declare
      Local : constant Supervision.Generation_Observation :=
        (Status => Supervision.Generation_Terminated, Snapshot => Snapshot (9, Supervision.Terminated));
      Remote : constant Tasks.Task_Observation := Conversion.To_Observation (Reference, Local);
   begin
      Assert (Remote.Status = Tasks.Task_Ended, "terminal generation was not reported as ended");
      Assert
        (Remote.Completion.Kind = Tasks.Unhandled_Exception,
         "terminal completion kind was not translated");
      Assert (Tasks.Exception_Name_Text (Remote.Completion) = "TEST_FAILURE", "exception name changed");
      Assert (Tasks.Message_Text (Remote.Completion) = "boom", "completion diagnostic changed");
   end;

   declare
      Local : constant Supervision.Generation_Observation :=
        (Status => Supervision.Generation_Replaced, Snapshot => Snapshot (10, Supervision.Running));
      Remote : constant Tasks.Task_Observation := Conversion.To_Observation (Reference, Local);
   begin
      Assert (Remote.Status = Tasks.Task_Replaced, "replacement generation was not reported");
      Assert
        (Tasks.Identity (Remote.Replacement) = Tasks.Identity (Reference),
         "replacement substituted the supervisor-local child identity");
      Assert
        (Tasks.Destination_Node (Remote.Replacement) = Tasks.Destination_Node (Reference),
         "replacement changed the observed node incarnation");
      Assert
        (Tasks.Generation (Remote.Replacement) = Tasks.Generation_From_Word (10),
         "replacement did not advance task generation");
   end;

   declare
      Timed_Out : constant Tasks.Task_Observation :=
        Conversion.To_Observation (Reference, (Status => Supervision.Observation_Timed_Out));
      Unreachable : constant Tasks.Task_Observation := (Status => Tasks.Peer_Unreachable);
      Node_Ended  : constant Tasks.Task_Observation := (Status => Tasks.Node_Incarnation_Ended);
   begin
      Assert (Timed_Out.Status = Tasks.Observation_Timed_Out, "timeout changed classification");
      Assert_Status (Unreachable, Tasks.Peer_Unreachable, "disconnect changed classification");
      Assert_Status (Node_Ended, Tasks.Node_Incarnation_Ended, "node death changed classification");
   end;

   declare
      Other : constant Tasks.Task_Reference :=
        Tasks.Make_Task_Reference (Node, Tasks.Task_ID_From_Word (702), Tasks.Generation_From_Word (9));
      Local : constant Supervision.Generation_Observation :=
        (Status => Supervision.Generation_Replaced, Snapshot => Snapshot (10, Supervision.Running));
      First  : constant Tasks.Task_Observation := Conversion.To_Observation (Reference, Local);
      Second : constant Tasks.Task_Observation := Conversion.To_Observation (Other, Local);
   begin
      Assert
        (Tasks.Identity (First.Replacement) /= Tasks.Identity (Second.Replacement),
         "distinct node-global task identities collided on one supervisor child identity");
   end;

   declare
      function Was_Rejected
        (Observed : Tasks.Task_Reference; Local : Supervision.Generation_Observation) return Boolean
      is
      begin
         declare
            Ignored : constant Tasks.Task_Observation := Conversion.To_Observation (Observed, Local);
            pragma Unreferenced (Ignored);
         begin
            return False;
         end;
      exception
         when Program_Error =>
            return True;
      end Was_Rejected;
   begin
      Assert
        (Was_Rejected
           (Reference,
            (Status => Supervision.Generation_Terminated, Snapshot => Snapshot (8, Supervision.Terminated))),
         "mismatched terminal generation was accepted");
      Assert
        (Was_Rejected
           (Reference,
            (Status => Supervision.Generation_Replaced, Snapshot => Snapshot (9, Supervision.Running))),
         "nonadvancing replacement generation was accepted");
      Assert
        (Was_Rejected (Tasks.No_Task, (Status => Supervision.Observation_Timed_Out)),
         "invalid observed reference was accepted");

      Termination.Kind := Supervision.No_Termination;
      Assert
        (Was_Rejected
           (Reference,
            (Status => Supervision.Generation_Terminated, Snapshot => Snapshot (9, Supervision.Terminated))),
         "terminal observation without a completion was accepted");
   end;
end Task_Lifecycle_Smoke;
