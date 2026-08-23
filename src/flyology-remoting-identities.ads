with Interfaces;

--  Defines transport-neutral node and live-session identity values. The
--  constructors import caller-supplied words; they do not generate entropy or
--  prove that an identity is unique or authenticated.

package Flyology.Remoting.Identities
  with Preelaborate
is

   subtype Identity_Word is Interfaces.Unsigned_64;

   --  Stable logical-node identity supplied by deployment configuration.
   type Node_ID is private;
   --  Identity supplied for exactly one running node incarnation.
   type Incarnation_ID is private;
   --  Identity supplied for exactly one live transport session.
   type Session_ID is private;

   No_Node_ID        : constant Node_ID;
   No_Incarnation_ID : constant Incarnation_ID;
   No_Session_ID     : constant Session_ID;

   --  Import high and low words without assigning an envelope byte encoding.
   function Node_ID_From_Words (High, Low : Identity_Word) return Node_ID;
   function Incarnation_ID_From_Words (High, Low : Identity_Word) return Incarnation_ID;
   function Session_ID_From_Words (High, Low : Identity_Word) return Session_ID;

   --  Report whether a node identity is not the all-zero sentinel.
   function Is_Valid (Value : Node_ID) return Boolean;
   --  Report whether an incarnation identity is not the all-zero sentinel.
   function Is_Valid (Value : Incarnation_ID) return Boolean;
   --  Report whether a session identity is not the all-zero sentinel.
   function Is_Valid (Value : Session_ID) return Boolean;

   --  Return the high semantic word of an identity value.
   function High_Word (Value : Node_ID) return Identity_Word;
   function High_Word (Value : Incarnation_ID) return Identity_Word;
   function High_Word (Value : Session_ID) return Identity_Word;

   --  Return the low semantic word of an identity value.
   function Low_Word (Value : Node_ID) return Identity_Word;
   function Low_Word (Value : Incarnation_ID) return Identity_Word;
   function Low_Word (Value : Session_ID) return Identity_Word;

   --  One logical node and one particular running incarnation.
   type Node_Reference is private;
   No_Node : constant Node_Reference;

   --  Combine caller-supplied stable and incarnation identities.
   function Make_Node_Reference (Stable : Node_ID; Incarnation : Incarnation_ID) return Node_Reference;
   --  Report whether both node-reference components are valid.
   function Is_Valid (Value : Node_Reference) return Boolean;
   --  Return the stable logical-node component.
   function Stable_ID (Value : Node_Reference) return Node_ID;
   --  Return the process-incarnation component.
   function Incarnation (Value : Node_Reference) return Incarnation_ID;

   --  One live session between role-stable initiator and acceptor nodes.
   type Session_Reference is private;
   No_Session : constant Session_Reference;

   --  Combine both node incarnations with a caller-supplied session identity.
   function Make_Session_Reference
     (Initiator : Node_Reference; Acceptor : Node_Reference; Identity : Session_ID) return Session_Reference;
   --  Report whether every session-reference component is valid.
   function Is_Valid (Value : Session_Reference) return Boolean;
   --  Return the node that initiated the session.
   function Initiator (Value : Session_Reference) return Node_Reference;
   --  Return the node that accepted the session.
   function Acceptor (Value : Session_Reference) return Node_Reference;
   --  Return the session identity component.
   function Identity (Value : Session_Reference) return Session_ID;

private
   type Identity_Value is record
      High : Identity_Word := 0;
      Low  : Identity_Word := 0;
   end record;

   type Node_ID is new Identity_Value;
   type Incarnation_ID is new Identity_Value;
   type Session_ID is new Identity_Value;

   No_Node_ID        : constant Node_ID := (others => 0);
   No_Incarnation_ID : constant Incarnation_ID := (others => 0);
   No_Session_ID     : constant Session_ID := (others => 0);

   type Node_Reference is record
      Stable      : Node_ID := No_Node_ID;
      Incarnation : Incarnation_ID := No_Incarnation_ID;
   end record;

   No_Node : constant Node_Reference := (others => <>);

   type Session_Reference is record
      Initiator_Node : Node_Reference := No_Node;
      Acceptor_Node  : Node_Reference := No_Node;
      Session        : Session_ID := No_Session_ID;
   end record;

   No_Session : constant Session_Reference := (others => <>);

end Flyology.Remoting.Identities;
