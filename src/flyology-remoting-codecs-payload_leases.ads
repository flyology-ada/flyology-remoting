with Ada.Streams;
with Flyology_Wire.Codecs;
with Flyology_Wire.Codecs.Contracts;

--  Applies one statically bound flyology_wire codec directly to opaque
--  payload leases. The adapter knows no lane, node, session, or envelope
--  representation. Every array borrow is callback-scoped and synchronous.
--  Instantiation raises Program_Error when Codec.Descriptor is invalid.
--
--  The lease provider must invoke each Process exactly once before returning
--  and must not retain it or any reference derived from Data. Capacity must
--  not exceed the writable Data'Length. A writable provider initializes
--  Length to the prior committed readable length and commits its returned
--  value only when Process returns normally. Both providers propagate Process
--  exceptions and retain the lease while those exceptions unwind. A readable
--  provider passes exactly the committed payload bytes with their arbitrary
--  array lower bound, not unused backing capacity or a partial prefix.

generic
   type Writable_Payload (<>) is limited private;
   type Received_Payload (<>) is limited private;

   with function Has_Writable (Payload : Writable_Payload) return Boolean;
   with function Has_Received (Payload : Received_Payload) return Boolean;
   with function Capacity (Payload : Writable_Payload) return Positive;

   with procedure With_Writable_Data
     (Payload : in out Writable_Payload;
      Process :
        not null access procedure (Data : in out Ada.Streams.Stream_Element_Array; Length : in out Natural));

   with procedure With_Readable_Data
     (Payload : Received_Payload;
      Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array));

   with package Codec is new Flyology_Wire.Codecs.Contracts (<>);
package Flyology.Remoting.Codecs.Payload_Leases is

   --  Measure Item before borrowing Payload, then encode directly into the
   --  borrowed storage. Reported failures do not commit a new readable length.
   procedure Encode
     (Item    : Codec.Value;
      Payload : in out Writable_Payload;
      Status  : out Flyology_Wire.Codecs.Encode_Status)
   with Pre => Has_Writable (Payload);

   --  Decode the complete received payload under the already validated
   --  writer identity. Payload remains borrowed only during the codec call.
   procedure Decode
     (Writer  : Flyology_Wire.Codecs.Schema_Identity;
      Payload : Received_Payload;
      Item    : out Codec.Value;
      Status  : out Flyology_Wire.Codecs.Decode_Status)
   with
     Pre =>
       Has_Received (Payload)
       and then Flyology_Wire.Codecs.Is_Valid (Writer);

end Flyology.Remoting.Codecs.Payload_Leases;
