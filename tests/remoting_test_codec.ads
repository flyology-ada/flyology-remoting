with Flyology_Wire.Codecs.Contracts;
with Flyology_Wire.Profiles;
with Interfaces;

--  Handwritten canonical Profile 1 codec used only by remoting integration
--  tests. The value contains one required unsigned field at tag 1.

package Remoting_Test_Codec is

   type Value is record
      Number : Interfaces.Unsigned_64 := 0;
      Valid  : Boolean := False;
   end record;

   --  Test-only schema fixture; these bytes are not a production identity or
   --  a public remoting protocol value.
   function Descriptor return Flyology_Wire.Codecs.Codec_Descriptor
   is
     ((Schema               =>
         (Family      => [0 => 16#52#, 1 => 16#4D#, others => 0],
          Fingerprint => [0 => 16#C1#, 31 => 16#01#, others => 0],
          Revision    => 1,
          Profile     => Flyology_Wire.Profiles.Canonical_Tagged),
       Maximum_Encoded_Size => Flyology_Wire.Codecs.Bounded (12)));

   procedure Measure
     (Item   : Value;
      Size   : out Flyology_Wire.Byte_Count;
      Status : out Flyology_Wire.Codecs.Measure_Status);

   procedure Encode
     (Item    : Value;
      Output  : in out Flyology_Wire.Octet_Array;
      Written : out Flyology_Wire.Octet_Count;
      Status  : out Flyology_Wire.Codecs.Encode_Status);

   procedure Decode
     (Writer : Flyology_Wire.Codecs.Schema_Identity;
      Input  : Flyology_Wire.Octet_Array;
      Item   : out Value;
      Status : out Flyology_Wire.Codecs.Decode_Status);

   package Contract is new
     Flyology_Wire.Codecs.Contracts
       (Value_Type       => Value,
        Value_Descriptor => Descriptor,
        Measure_Value    => Measure,
        Encode_Value     => Encode,
        Decode_Value     => Decode);

end Remoting_Test_Codec;
