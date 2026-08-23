with Flyology.Supervision;

--  Converts Flyology's exact local supervision observations into portable
--  remoting values. Waiting and restart policy remain owned by the concrete
--  local supervisor.

package Flyology.Remoting.Tasks.From_Supervision is

   function To_Completion
     (Item : Flyology.Supervision.Termination_Summary) return Completion_Summary;

   --  Preserve the node-global task identity being observed. A Flyology
   --  Child_Id belongs to one supervisor controller and is not a node-global
   --  remoting identity. Incoherent observations raise Program_Error.
   function To_Observation
     (Observed : Task_Reference; Item : Flyology.Supervision.Generation_Observation)
      return Task_Observation;

end Flyology.Remoting.Tasks.From_Supervision;
