with Flyology.Supervision;

--  Binds a registry-retained local supervisor handle to one exact remoting
--  task reference. The registry remains responsible for mapping its
--  node-global Task_ID to the correct private handle.

generic
   type Local_Supervisor is limited private;
   type Local_Handle is private;

   --  Return the exact generation stored in Handle.
   with function Handle_Generation
     (Handle : Local_Handle) return Flyology.Supervision.Generation;

   --  Atomically check/register the exact handle and never follow a
   --  replacement, as Flyology's static and family Wait_Termination do.
   with function Wait_Termination
     (Item    : in out Local_Supervisor;
      Handle  : Local_Handle;
      Timeout : Duration) return Flyology.Supervision.Generation_Observation;

package Flyology.Remoting.Tasks.Local_Observers is

   --  Wait for the exact local generation that the registry maps to Observed.
   --  The registry must supply the matching private handle. Invalid values or
   --  a handle/reference generation mismatch raise Program_Error before
   --  Wait_Termination is called. Provider and capacity exceptions propagate.
   function Observe_Exact
     (Item     : in out Local_Supervisor;
      Handle   : Local_Handle;
      Observed : Task_Reference;
      Timeout  : Duration := -1.0) return Task_Observation;

end Flyology.Remoting.Tasks.Local_Observers;
