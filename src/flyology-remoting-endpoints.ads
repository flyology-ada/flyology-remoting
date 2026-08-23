with Interfaces;
with Flyology.Remoting.Identities;

--  Defines generation-stamped endpoint references. An endpoint reference is
--  a value and contains no Ada access value, task identity, or transport
--  object.

package Flyology.Remoting.Endpoints
  with Preelaborate
is

   subtype Endpoint_Word is Interfaces.Unsigned_64;

   --  Node-local directory position. Zero is invalid.
   type Endpoint_Slot is private;
   --  Nonwrapping reuse generation. Zero is invalid.
   type Endpoint_Generation is private;

   No_Endpoint_Slot       : constant Endpoint_Slot;
   No_Endpoint_Generation : constant Endpoint_Generation;

   --  Import scalar values without assigning an envelope byte encoding.
   function Slot_From_Word (Value : Endpoint_Word) return Endpoint_Slot;
   function Generation_From_Word (Value : Endpoint_Word) return Endpoint_Generation;
   --  Return the semantic scalar value.
   function To_Word (Value : Endpoint_Slot) return Endpoint_Word;
   function To_Word (Value : Endpoint_Generation) return Endpoint_Word;
   --  Report whether a slot or generation is not its zero sentinel.
   function Is_Valid (Value : Endpoint_Slot) return Boolean;
   function Is_Valid (Value : Endpoint_Generation) return Boolean;

   --  Transport-neutral destination value for one node incarnation and slot generation.
   type Endpoint_Reference is private;
   No_Endpoint : constant Endpoint_Reference;

   --  Combine node, slot, and generation components without generating them.
   function Make_Endpoint_Reference
     (Node       : Identities.Node_Reference;
      Slot       : Endpoint_Slot;
      Generation : Endpoint_Generation) return Endpoint_Reference;
   --  Report whether every endpoint-reference component is valid.
   function Is_Valid (Value : Endpoint_Reference) return Boolean;
   --  Return the destination node incarnation.
   function Destination_Node (Value : Endpoint_Reference) return Identities.Node_Reference;
   --  Return the node-local slot.
   function Slot (Value : Endpoint_Reference) return Endpoint_Slot;
   --  Return the slot-reuse generation.
   function Generation (Value : Endpoint_Reference) return Endpoint_Generation;

private
   type Endpoint_Slot is new Endpoint_Word;
   type Endpoint_Generation is new Endpoint_Word;

   No_Endpoint_Slot       : constant Endpoint_Slot := 0;
   No_Endpoint_Generation : constant Endpoint_Generation := 0;

   type Endpoint_Reference is record
      Node       : Identities.Node_Reference := Identities.No_Node;
      Slot       : Endpoint_Slot := No_Endpoint_Slot;
      Generation : Endpoint_Generation := No_Endpoint_Generation;
   end record;

   No_Endpoint : constant Endpoint_Reference := (others => <>);

end Flyology.Remoting.Endpoints;
