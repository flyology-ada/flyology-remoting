with Flyology.Remoting.Transports.In_Process_Compound;

procedure Compound_Hook_Elision_Probe is
   package Probe is new
     Flyology.Remoting.Transports.In_Process_Compound
       (Queue_Capacity => 1, Maximum_Concurrent_Builders => 1);
   pragma Unreferenced (Probe);
begin
   null;
end Compound_Hook_Elision_Probe;
