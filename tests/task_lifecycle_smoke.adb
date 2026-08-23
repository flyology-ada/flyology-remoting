with Ada.Real_Time;
with Flyology;
with Flyology.Execution_Groups;
with Flyology.Remoting.Identities;
with Flyology.Remoting.Tasks;
with Flyology.Remoting.Tasks.From_Supervision;
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
     Tasks.Make_Task_Reference (Node, Tasks.Task_ID_From_Word (7), Tasks.Generation_From_Word (9));

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

begin
   Assert (Tasks.Is_Valid (Reference), "valid remote task reference was rejected");
   Assert (Tasks.Destination_Node (Reference) = Node, "remote task node identity changed");
   Assert (Tasks.Identity (Reference) = Tasks.Task_ID_From_Word (7), "remote task identity changed");
   Assert
     (Tasks.Generation (Reference) = Tasks.Generation_From_Word (9),
      "remote task generation changed");
   Assert (not Tasks.Is_Valid (Tasks.No_Task), "invalid remote task sentinel was accepted");

   Termination.Kind := Supervision.Unhandled_Exception;
   Termination.Exception_Name_Length := 12;
   Termination.Exception_Name (1 .. 12) := "TEST_FAILURE";
   Termination.Message_Length := 4;
   Termination.Message (1 .. 4) := "boom";

   declare
      Local : constant Supervision.Generation_Observation :=
        (Status => Supervision.Generation_Terminated, Snapshot => Snapshot (9, Supervision.Terminated));
      Remote : constant Tasks.Task_Observation := Conversion.To_Observation (Node, Local);
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
      Remote : constant Tasks.Task_Observation := Conversion.To_Observation (Node, Local);
   begin
      Assert (Remote.Status = Tasks.Task_Replaced, "replacement generation was not reported");
      Assert
        (Tasks.Identity (Remote.Replacement) = Tasks.Identity (Reference),
         "replacement changed logical task identity");
      Assert
        (Tasks.Generation (Remote.Replacement) = Tasks.Generation_From_Word (10),
         "replacement did not advance task generation");
   end;

   declare
      Timed_Out : constant Tasks.Task_Observation :=
        Conversion.To_Observation (Node, (Status => Supervision.Observation_Timed_Out));
      Unreachable : constant Tasks.Task_Observation := (Status => Tasks.Peer_Unreachable);
      Node_Ended  : constant Tasks.Task_Observation := (Status => Tasks.Node_Incarnation_Ended);
   begin
      Assert (Timed_Out.Status = Tasks.Observation_Timed_Out, "timeout changed classification");
      Assert_Status (Unreachable, Tasks.Peer_Unreachable, "disconnect changed classification");
      Assert_Status (Node_Ended, Tasks.Node_Incarnation_Ended, "node death changed classification");
   end;
end Task_Lifecycle_Smoke;
