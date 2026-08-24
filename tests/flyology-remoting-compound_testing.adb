with Flyology.Remoting.Compound_Test_Hooks;

package body Flyology.Remoting.Compound_Testing is

   procedure Arm (Point : Failure_Point) is
   begin
      Flyology.Remoting.Compound_Test_Hooks.Arm
        (Flyology.Remoting.Compound_Test_Hooks.Failure_Point'Val (Failure_Point'Pos (Point)));
   end Arm;

   procedure Reset is
   begin
      Flyology.Remoting.Compound_Test_Hooks.Reset;
   end Reset;

end Flyology.Remoting.Compound_Testing;
