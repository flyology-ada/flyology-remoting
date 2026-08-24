--  Disabled compound-transport failure injection selected by the owning
--  project. Imported-only declarations expose any missed static guard.
private package Flyology.Remoting.Compound_Test_Hooks is

   --  Keep this a literal compile-time constant. GNAT removes guarded calls
   --  even at -O0 when this source is selected.
   Enabled : constant Boolean := False;

   type Failure_Point is
     (After_Builder_Reservation,
      After_Header_Slot_Allocation,
      After_Header_Move,
      After_Queue_Transfer);

   procedure Arm (Point : Failure_Point)
   with Import, External_Name => "flyology_remoting_disabled_hook_must_be_elided_compound_arm";

   procedure Reset
   with Import, External_Name => "flyology_remoting_disabled_hook_must_be_elided_compound_reset";

   procedure Raise_If_Armed (Point : Failure_Point)
   with Import, External_Name => "flyology_remoting_disabled_hook_must_be_elided_compound_raise";

end Flyology.Remoting.Compound_Test_Hooks;
