package body Flyology.Remoting.Tasks is

   function Task_ID_From_Word (Value : Task_Word) return Task_ID is
     (Task_ID (Value));

   function Generation_From_Word (Value : Task_Word) return Task_Generation is
     (Task_Generation (Value));

   function To_Word (Value : Task_ID) return Task_Word is
     (Task_Word (Value));

   function To_Word (Value : Task_Generation) return Task_Word is
     (Task_Word (Value));

   function Is_Valid (Value : Task_ID) return Boolean is
     (Value /= No_Task_ID);

   function Is_Valid (Value : Task_Generation) return Boolean is
     (Value /= No_Task_Generation);

   function Make_Task_Reference
     (Node       : Identities.Node_Reference;
      Identity   : Task_ID;
      Generation : Task_Generation) return Task_Reference
   is
     ((Node => Node, Identity => Identity, Generation => Generation));

   function Is_Valid (Value : Task_Reference) return Boolean is
     (Identities.Is_Valid (Value.Node)
      and then Is_Valid (Value.Identity)
      and then Is_Valid (Value.Generation));

   function Destination_Node (Value : Task_Reference) return Identities.Node_Reference is
     (Value.Node);

   function Identity (Value : Task_Reference) return Task_ID is
     (Value.Identity);

   function Generation (Value : Task_Reference) return Task_Generation is
     (Value.Generation);

end Flyology.Remoting.Tasks;
