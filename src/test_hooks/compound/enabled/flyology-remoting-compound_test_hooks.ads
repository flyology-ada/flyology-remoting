--  Enabled compound-transport failure injection selected by the owning
--  project. The hooks are one-shot and introduce no waits.
private package Flyology.Remoting.Compound_Test_Hooks is

   --  Keep this a literal compile-time constant. GNAT removes guarded calls
   --  even at -O0 when the disabled source is selected.
   Enabled : constant Boolean := True;

   type Failure_Point is
     (After_Builder_Reservation,
      After_Header_Slot_Allocation,
      After_Header_Move,
      After_Queue_Transfer);

   procedure Arm (Point : Failure_Point);

   procedure Reset;

   procedure Raise_If_Armed (Point : Failure_Point);

end Flyology.Remoting.Compound_Test_Hooks;
