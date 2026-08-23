with Flyology.Remoting.Transports.In_Process;
with Flyology_Wire.Codecs;
with Flyology_Wire.Codecs.Contracts;

--  Thin in-process facade over the transport-independent payload-lease codec
--  adapter. Encoding writes into the owned pool slot, and decoding observes
--  received storage only for the dynamic extent of the codec call.

generic
   with package Transport is new Flyology.Remoting.Transports.In_Process (<>);
   with package Codec is new Flyology_Wire.Codecs.Contracts (<>);
package Flyology.Remoting.Codecs.In_Process is

   --  Measure Item and encode it directly into Payload. A failed encode leaves
   --  the prior readable length unchanged. The codec contract keeps payload
   --  bytes unchanged on a reported failure.
   procedure Encode
     (Item    : Codec.Value;
      Payload : in out Transport.Writable_Payload;
      Status  : out Flyology_Wire.Codecs.Encode_Status)
   with Pre => Transport.Has_Payload (Payload);

   --  Decode the complete received payload using the structurally validated
   --  writer identity supplied by the enclosing message or envelope layer.
   procedure Decode
     (Writer  : Flyology_Wire.Codecs.Schema_Identity;
      Payload : Transport.Received_Payload;
      Item    : out Codec.Value;
      Status  : out Flyology_Wire.Codecs.Decode_Status)
   with
     Pre =>
       Transport.Has_Payload (Payload)
       and then Flyology_Wire.Codecs.Is_Valid (Writer);

end Flyology.Remoting.Codecs.In_Process;
