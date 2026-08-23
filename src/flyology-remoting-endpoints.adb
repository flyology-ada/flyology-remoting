package body Flyology.Remoting.Endpoints is
   function Slot_From_Word (Value : Endpoint_Word) return Endpoint_Slot is
     (Endpoint_Slot (Value));

   function Generation_From_Word (Value : Endpoint_Word) return Endpoint_Generation is
     (Endpoint_Generation (Value));

   function To_Word (Value : Endpoint_Slot) return Endpoint_Word is
     (Endpoint_Word (Value));

   function To_Word (Value : Endpoint_Generation) return Endpoint_Word is
     (Endpoint_Word (Value));

   function Is_Valid (Value : Endpoint_Slot) return Boolean is
     (Value /= No_Endpoint_Slot);

   function Is_Valid (Value : Endpoint_Generation) return Boolean is
     (Value /= No_Endpoint_Generation);

   function Make_Endpoint_Reference
     (Node       : Identities.Node_Reference;
      Slot       : Endpoint_Slot;
      Generation : Endpoint_Generation) return Endpoint_Reference is
     (Node => Node, Slot => Slot, Generation => Generation);

   function Is_Valid (Value : Endpoint_Reference) return Boolean is
     (Identities.Is_Valid (Value.Node)
      and then Is_Valid (Value.Slot)
      and then Is_Valid (Value.Generation));

   function Destination_Node (Value : Endpoint_Reference) return Identities.Node_Reference is
     (Value.Node);

   function Slot (Value : Endpoint_Reference) return Endpoint_Slot is (Value.Slot);

   function Generation (Value : Endpoint_Reference) return Endpoint_Generation is
     (Value.Generation);

end Flyology.Remoting.Endpoints;
