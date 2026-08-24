package body Flyology.Remoting.Compound_Test_Hooks is

   type Armed_Array is array (Failure_Point) of Boolean;

   protected Control is
      procedure Arm (Point : Failure_Point);
      procedure Reset;
      procedure Consume (Point : Failure_Point; Was_Armed : out Boolean);
   private
      Armed : Armed_Array := (others => False);
   end Control;

   protected body Control is
      procedure Arm (Point : Failure_Point) is
      begin
         Armed (Point) := True;
      end Arm;

      procedure Reset is
      begin
         Armed := (others => False);
      end Reset;

      procedure Consume (Point : Failure_Point; Was_Armed : out Boolean) is
      begin
         Was_Armed := Armed (Point);
         Armed (Point) := False;
      end Consume;
   end Control;

   procedure Arm (Point : Failure_Point) is
   begin
      Control.Arm (Point);
   end Arm;

   procedure Reset is
   begin
      Control.Reset;
   end Reset;

   procedure Raise_If_Armed (Point : Failure_Point) is
      Was_Armed : Boolean;
   begin
      Control.Consume (Point, Was_Armed);
      if Was_Armed then
         raise Program_Error with "injected compound transport failure";
      end if;
   end Raise_If_Armed;

end Flyology.Remoting.Compound_Test_Hooks;
