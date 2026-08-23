with Flyology_Wire;

--  Defines transport-neutral message identity values. Constructors import
--  caller-supplied bytes; they do not generate identities or enforce session
--  nonreuse.
package Flyology.Remoting.Messages
  with Preelaborate
is
   type Message_ID is private;

   No_Message_ID : constant Message_ID;

   type Message_ID_Bytes is
     array (Flyology_Wire.Octet_Offset range 0 .. 15) of Flyology_Wire.Octet;

   --  Import the canonical ordered 16-octet value.
   function Message_ID_From_Bytes (Value : Message_ID_Bytes) return Message_ID;

   --  Return the canonical ordered 16-octet value.
   function To_Bytes (Value : Message_ID) return Message_ID_Bytes;

   --  The all-zero identity is reserved as the invalid sentinel.
   function Is_Valid (Value : Message_ID) return Boolean;

private
   type Message_ID is new Message_ID_Bytes;

   No_Message_ID : constant Message_ID := (others => 0);
end Flyology.Remoting.Messages;
