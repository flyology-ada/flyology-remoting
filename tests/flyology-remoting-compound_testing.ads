--  Smoke-test control surface. This child is not part of libFlyology_Remoting.
package Flyology.Remoting.Compound_Testing is

   type Failure_Point is
     (After_Builder_Reservation,
      After_Header_Slot_Allocation,
      After_Header_Move,
      After_Queue_Transfer);

   procedure Arm (Point : Failure_Point);

   procedure Reset;

end Flyology.Remoting.Compound_Testing;
