package body Flyology.Remoting.Identities is
   use type Identity_Word;

   function Node_ID_From_Words (High, Low : Identity_Word) return Node_ID is
     (High => High, Low => Low);

   function Incarnation_ID_From_Words (High, Low : Identity_Word) return Incarnation_ID is
     (High => High, Low => Low);

   function Session_ID_From_Words (High, Low : Identity_Word) return Session_ID is
     (High => High, Low => Low);

   function Is_Valid (Value : Node_ID) return Boolean is
     (Value.High /= 0 or else Value.Low /= 0);

   function Is_Valid (Value : Incarnation_ID) return Boolean is
     (Value.High /= 0 or else Value.Low /= 0);

   function Is_Valid (Value : Session_ID) return Boolean is
     (Value.High /= 0 or else Value.Low /= 0);

   function High_Word (Value : Node_ID) return Identity_Word is (Value.High);
   function High_Word (Value : Incarnation_ID) return Identity_Word is (Value.High);
   function High_Word (Value : Session_ID) return Identity_Word is (Value.High);

   function Low_Word (Value : Node_ID) return Identity_Word is (Value.Low);
   function Low_Word (Value : Incarnation_ID) return Identity_Word is (Value.Low);
   function Low_Word (Value : Session_ID) return Identity_Word is (Value.Low);

   function Make_Node_Reference (Stable : Node_ID; Incarnation : Incarnation_ID) return Node_Reference is
     (Stable => Stable, Incarnation => Incarnation);

   function Is_Valid (Value : Node_Reference) return Boolean is
     (Is_Valid (Value.Stable) and then Is_Valid (Value.Incarnation));

   function Stable_ID (Value : Node_Reference) return Node_ID is (Value.Stable);

   function Incarnation (Value : Node_Reference) return Incarnation_ID is (Value.Incarnation);

   function Make_Session_Reference
     (Initiator : Node_Reference; Acceptor : Node_Reference; Identity : Session_ID)
      return Session_Reference is
     (Initiator_Node => Initiator, Acceptor_Node => Acceptor, Session => Identity);

   function Is_Valid (Value : Session_Reference) return Boolean is
     (Is_Valid (Value.Initiator_Node)
      and then Is_Valid (Value.Acceptor_Node)
      and then Is_Valid (Value.Session));

   function Initiator (Value : Session_Reference) return Node_Reference is (Value.Initiator_Node);

   function Acceptor (Value : Session_Reference) return Node_Reference is (Value.Acceptor_Node);

   function Identity (Value : Session_Reference) return Session_ID is (Value.Session);

end Flyology.Remoting.Identities;
