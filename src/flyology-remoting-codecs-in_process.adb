with Flyology.Remoting.Codecs.Payload_Leases;

package body Flyology.Remoting.Codecs.In_Process is
   package Adapter is new
     Flyology.Remoting.Codecs.Payload_Leases
       (Writable_Payload  => Transport.Writable_Payload,
        Received_Payload  => Transport.Received_Payload,
        Has_Writable      => Transport.Has_Payload,
        Has_Received      => Transport.Has_Payload,
        Capacity          => Transport.Payload_Capacity,
        With_Writable_Data => Transport.With_Writable_Data,
        With_Readable_Data => Transport.With_Readable_Data,
        Codec             => Codec);

   procedure Encode
      (Item    : Codec.Value;
       Payload : in out Transport.Writable_Payload;
       Status  : out Flyology_Wire.Codecs.Encode_Status)
   is
   begin
      Adapter.Encode (Item, Payload, Status);
   end Encode;

   procedure Decode
      (Writer  : Flyology_Wire.Codecs.Schema_Identity;
       Payload : Transport.Received_Payload;
       Item    : out Codec.Value;
       Status  : out Flyology_Wire.Codecs.Decode_Status)
   is
   begin
      Adapter.Decode (Writer, Payload, Item, Status);
   end Decode;
end Flyology.Remoting.Codecs.In_Process;
