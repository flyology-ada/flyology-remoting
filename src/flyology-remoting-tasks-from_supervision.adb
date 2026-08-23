package body Flyology.Remoting.Tasks.From_Supervision is
   use type Flyology.Supervision.Termination_Kind;
   use type Task_Word;

   function To_Completion
     (Item : Flyology.Supervision.Termination_Summary) return Completion_Summary
   is
      Kind : constant Completion_Kind :=
        (case Item.Kind is
            when Flyology.Supervision.No_Termination       => Unknown_Completion,
            when Flyology.Supervision.Normal_Return        => Normal_Return,
            when Flyology.Supervision.Unhandled_Exception  => Unhandled_Exception,
            when Flyology.Supervision.Cancelled            => Cancelled,
            when Flyology.Supervision.Supervisor_Shutdown  => Supervisor_Shutdown,
            when Flyology.Supervision.Abnormal_Completion  => Abnormal_Completion,
            when Flyology.Supervision.Activation_Failure   => Activation_Failure,
            when Flyology.Supervision.Readiness_Timeout    => Readiness_Timeout,
            when Flyology.Supervision.Restart_Requested    => Restart_Requested,
            when Flyology.Supervision.Unhealthy            => Unhealthy,
            when Flyology.Supervision.Stop_Timeout         => Stop_Timeout,
            when Flyology.Supervision.Stuck                => Stuck,
            when Flyology.Supervision.Policy_Exhaustion    => Policy_Exhaustion);
      Result : Completion_Summary;
   begin
      Result.Kind := Kind;
      Result.Exception_Name_Length := Exception_Name_Length (Item.Exception_Name_Length);
      Result.Exception_Name_Truncated := Item.Exception_Name_Truncated;
      Result.Exception_Name := Item.Exception_Name;
      Result.Message_Length := Diagnostic_Length (Item.Message_Length);
      Result.Message_Truncated := Item.Message_Truncated;
      Result.Message := Item.Message;
      return Result;
   end To_Completion;

   function To_Observation
     (Observed : Task_Reference; Item : Flyology.Supervision.Generation_Observation)
      return Task_Observation
   is
   begin
      if not Is_Valid (Observed) then
         raise Program_Error with "invalid remoting task reference";
      end if;

      case Item.Status is
         when Flyology.Supervision.Observation_Timed_Out =>
            return (Status => Observation_Timed_Out);

         when Flyology.Supervision.Generation_Terminated =>
            if Task_Word (Item.Snapshot.Generation) /= To_Word (Generation (Observed)) then
               raise Program_Error with "terminal supervisor generation does not match observed task";
            end if;
            if Item.Snapshot.Termination.Kind = Flyology.Supervision.No_Termination then
               raise Program_Error with "terminal supervisor observation has no completion";
            end if;
            return (Status => Task_Ended, Completion => To_Completion (Item.Snapshot.Termination));

         when Flyology.Supervision.Generation_Replaced =>
            if Task_Word (Item.Snapshot.Generation) <= To_Word (Generation (Observed)) then
               raise Program_Error with "replacement supervisor generation did not advance";
            end if;
            return
              (Status      => Task_Replaced,
               Replacement =>
                 Make_Task_Reference
                   (Destination_Node (Observed),
                    Identity (Observed),
                    Generation_From_Word (Task_Word (Item.Snapshot.Generation))));
      end case;
   end To_Observation;

end Flyology.Remoting.Tasks.From_Supervision;
