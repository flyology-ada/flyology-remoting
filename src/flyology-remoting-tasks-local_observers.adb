with Flyology.Remoting.Tasks.From_Supervision;

package body Flyology.Remoting.Tasks.Local_Observers is
   use type Task_Word;

   function Observe_Exact
     (Item     : in out Local_Supervisor;
      Handle   : Local_Handle;
      Observed : Task_Reference;
      Timeout  : Duration := -1.0) return Task_Observation
   is
   begin
      if not Is_Valid (Observed) then
         raise Program_Error with "invalid remoting task reference";
      end if;

      if Task_Word (Handle_Generation (Handle)) /= To_Word (Generation (Observed)) then
         raise Program_Error with "local supervisor handle does not match observed generation";
      end if;

      return
        From_Supervision.To_Observation
          (Observed, Wait_Termination (Item, Handle, Timeout));
   end Observe_Exact;

end Flyology.Remoting.Tasks.Local_Observers;
