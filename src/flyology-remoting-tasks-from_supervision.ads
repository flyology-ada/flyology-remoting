with Flyology.Remoting.Identities;
with Flyology.Supervision;

--  Converts Flyology's exact local supervision observations into portable
--  remoting values. Waiting and restart policy remain owned by the concrete
--  local supervisor.

package Flyology.Remoting.Tasks.From_Supervision is

   function To_Task_Reference
     (Node : Identities.Node_Reference; Handle : Flyology.Supervision.Child_Handle) return Task_Reference;

   function To_Completion
     (Item : Flyology.Supervision.Termination_Summary) return Completion_Summary;

   function To_Observation
     (Node : Identities.Node_Reference; Item : Flyology.Supervision.Generation_Observation)
      return Task_Observation;

end Flyology.Remoting.Tasks.From_Supervision;
