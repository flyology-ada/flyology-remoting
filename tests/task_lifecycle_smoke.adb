with Ada.Real_Time;
with Ada.Task_Identification;
with Flyology;
with Flyology.Cancellation;
with Flyology.Execution_Groups;
with Flyology.Remoting.Identities;
with Flyology.Remoting.Tasks;
with Flyology.Remoting.Tasks.From_Supervision;
with Flyology.Remoting.Tasks.Local_Observers;
with Flyology.Supervision;
with Flyology.Supervision.Families;
with Flyology.Supervision.Input_Task_Generations;
with System.Multiprocessors;

procedure Task_Lifecycle_Smoke is
   package Identities renames Flyology.Remoting.Identities;
   package Tasks renames Flyology.Remoting.Tasks;
   package Conversion renames Flyology.Remoting.Tasks.From_Supervision;
   package Supervision renames Flyology.Supervision;

   use type Ada.Real_Time.Time;
   use type Identities.Node_Reference;
   use type Supervision.Child_State;
   use type Tasks.Completion_Kind;
   use type Tasks.Observation_Status;
   use type Tasks.Task_Generation;
   use type Tasks.Task_ID;
   use type Tasks.Task_Word;

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

   procedure Run_Family_Observer_Integration is
      type Family_Request is (Only_Request);
      type Family_Context is limited null record;

      task type Family_Task
        (State   : not null access Family_Context;
         Input   : not null access constant Family_Request;
         Control : not null access Supervision.Generation_Control)
        with CPU => System.Multiprocessors.Not_A_Specific_CPU
      is
         pragma Task_Info (Flyology.Native_Task);
      end Family_Task;

      task body Family_Task is
         pragma Unreferenced (State, Input);
      begin
         Supervision.Mark_Ready (Control.all);
         loop
            exit when Supervision.Stop_Requested (Control.all);
            delay 0.001;
         end loop;
         raise Flyology.Cancellation.Operation_Cancelled;
      end Family_Task;

      function Create_Family_Task
        (State   : not null access Family_Context;
         Input   : not null access constant Family_Request;
         Control : not null access Supervision.Generation_Control) return Family_Task is
      begin
         return Subject : Family_Task (State, Input, Control);
      end Create_Family_Task;

      function Task_Identity
        (Subject : in out Family_Task) return Ada.Task_Identification.Task_Id is
        (Subject'Identity);

      procedure Abort_Family_Task (Subject : in out Family_Task) is
      begin
         abort Subject;
      end Abort_Family_Task;

      package Family_Child is new
        Flyology.Supervision.Input_Task_Generations
          (Input_Type          => Family_Request,
           Application_Context => Family_Context,
           Generation_Task     => Family_Task,
           Create              => Create_Family_Task,
           Task_Identity       => Task_Identity,
           Abort_Task          => Abort_Family_Task);

      procedure Run_Family_Generation
        (State   : aliased in out Family_Context;
         Input   : Family_Request;
         Control : aliased in out Supervision.Generation_Control;
         Result  : out Supervision.Generation_Result) is
      begin
         Family_Child.Run (State, Input, Control, Result);
      end Run_Family_Generation;

      Family_Policy : constant Supervision.Child_Specification :=
        (Restart           => Supervision.Never,
         Impact            => Supervision.Escalate,
         Recovery          => Supervision.Default_Recovery_Limits,
         Stopping          => Supervision.Default_Stop_Policy,
         Readiness_Timeout => Ada.Real_Time.Seconds (1),
         Restart_Safe      => True,
         Task_Model        => Flyology.Native_Task,
         Has_Group         => False,
         Group             => 0);

      package Families is new
        Flyology.Supervision.Families
          (Request             => Family_Request,
           Application_Context => Family_Context,
           Run_One_Generation  => Run_Family_Generation,
           Policy              => Family_Policy,
           First_Child_Id      => 9_000_000_000,
           Maximum_Children    => 2,
           Event_Capacity      => 4,
           Monitor_Capacity    => 2);

      package Family_Observer is new
        Tasks.Local_Observers
          (Local_Supervisor  => Families.Family,
           Local_Handle      => Supervision.Child_Handle,
           Handle_Generation => Supervision.Current_Generation,
           Wait_Termination  => Families.Wait_Termination);

      State  : aliased Family_Context;
      Item   : aliased Families.Family;
      Result : Supervision.Supervisor_Result;

      task Owner is
         entry Start;
         entry Join;
      end Owner;

      task body Owner is
      begin
         accept Start;
         Families.Run (Item, State, Result);
         accept Join;
      end Owner;

      procedure Shutdown_And_Join is
      begin
         Families.Request_Shutdown (Item);
         Owner.Join;
      end Shutdown_And_Join;

      Deadline : Ada.Real_Time.Time;
      Handle   : Supervision.Child_Handle;
   begin
      Owner.Start;
      begin
         pragma Warnings (Off, "variable ""Item"" is not modified in loop body");
         pragma Warnings (Off, "possible infinite loop");
         Deadline := Ada.Real_Time.Clock + Ada.Real_Time.Seconds (2);
         loop
            exit when Families.Accepting (Item);
            if Ada.Real_Time.Clock >= Deadline then
               raise Program_Error with "real family did not open admission";
            end if;
            delay 0.001;
         end loop;

         Families.Start (Item, Only_Request, Handle);
         Deadline := Ada.Real_Time.Clock + Ada.Real_Time.Seconds (2);
         loop
            exit when Families.Current (Item, Handle).Ready;
            if Ada.Real_Time.Clock >= Deadline then
               declare
                  Current : constant Supervision.Child_Snapshot := Families.Current (Item, Handle);
               begin
                  raise Program_Error with
                    "real family generation did not become ready: "
                    & Supervision.Child_State'Image (Current.State)
                    & ", live="
                    & Boolean'Image (Current.Live)
                    & ", termination="
                    & Supervision.Termination_Kind'Image (Current.Termination.Kind)
                    & ", exception="
                    & Supervision.Exception_Name_Text (Current.Termination)
                    & ", message="
                    & Supervision.Message_Text (Current.Termination);
               end;
            end if;
            delay 0.001;
         end loop;
         pragma Warnings (On, "possible infinite loop");
         pragma Warnings (On, "variable ""Item"" is not modified in loop body");

         declare
            Observed : constant Tasks.Task_Reference :=
              Tasks.Make_Task_Reference
                (Node,
                 Tasks.Task_ID_From_Word (703),
                 Tasks.Generation_From_Word
                   (Tasks.Task_Word (Supervision.Current_Generation (Handle))));
            Observation : constant Tasks.Task_Observation :=
              Family_Observer.Observe_Exact (Item, Handle, Observed, Timeout => 0.0);
            Mismatch_Rejected : Boolean := False;
            Mismatch_Returned : Boolean := False;
         begin
            Assert
              (Observation.Status = Tasks.Observation_Timed_Out,
               "real family running wait changed timeout status");

            begin
               declare
                  Mismatched : constant Tasks.Task_Reference :=
                    Tasks.Make_Task_Reference
                      (Node,
                       Tasks.Task_ID_From_Word (703),
                       Tasks.Generation_From_Word (Tasks.To_Word (Tasks.Generation (Observed)) + 1));
                  Ignored : constant Tasks.Task_Observation :=
                    Family_Observer.Observe_Exact (Item, Handle, Mismatched, Timeout => 0.0);
                  pragma Unreferenced (Ignored);
               begin
                  Mismatch_Returned := True;
               end;
            exception
               when Program_Error =>
                  Mismatch_Rejected := True;
            end;
            Assert
              (Mismatch_Rejected and then not Mismatch_Returned,
               "real family adapter accepted a mismatched remoting generation");
         end;

         Shutdown_And_Join;
      exception
         when others =>
            Shutdown_And_Join;
            raise;
      end;
   end Run_Family_Observer_Integration;

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
   Run_Family_Observer_Integration;

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
