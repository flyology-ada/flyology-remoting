with Ada.Streams;
with Flyology_Wire;

package body Flyology.Remoting.Codecs.In_Process is
   use type Flyology_Wire.Byte_Count;
   use type Flyology_Wire.Codecs.Encode_Status;
   use type Flyology_Wire.Codecs.Measure_Status;
   use type Flyology_Wire.Octet_Count;

   procedure Encode
     (Item    : Codec.Value;
      Payload : in out Transport.Writable_Payload;
      Status  : out Flyology_Wire.Codecs.Encode_Status)
   is
      Size           : Flyology_Wire.Byte_Count;
      Measure_Result : Flyology_Wire.Codecs.Measure_Status;

      procedure Write
        (Data : in out Ada.Streams.Stream_Element_Array;
         Length : in out Natural)
      is
         Written : Flyology_Wire.Octet_Count;
      begin
         Codec.Encode (Item, Data, Written, Status);
         if Status = Flyology_Wire.Codecs.Encoded then
            if Written /= Flyology_Wire.To_Octet_Count (Size) then
               raise Program_Error with "wire codec encode length differs from exact measurement";
            end if;
            Length := Natural (Written);
         end if;
      end Write;
   begin
      Codec.Measure (Item, Size, Measure_Result);
      case Measure_Result is
         when Flyology_Wire.Codecs.Invalid_Value =>
            Status := Flyology_Wire.Codecs.Invalid_Value;
            return;
         when Flyology_Wire.Codecs.Size_Overflow =>
            Status := Flyology_Wire.Codecs.Size_Overflow;
            return;
         when Flyology_Wire.Codecs.Measured =>
            null;
      end case;

      if not Flyology_Wire.Fits_In_Buffer (Size)
        or else Size > Flyology_Wire.Byte_Count (Transport.Payload_Capacity (Payload))
      then
         Status := Flyology_Wire.Codecs.Destination_Too_Small;
         return;
      end if;

      Transport.With_Writable_Data (Payload, Write'Access);
   end Encode;

   procedure Decode
     (Writer  : Flyology_Wire.Codecs.Schema_Identity;
      Payload : Transport.Received_Payload;
      Item    : out Codec.Value;
      Status  : out Flyology_Wire.Codecs.Decode_Status)
   is
      procedure Read (Data : Ada.Streams.Stream_Element_Array) is
      begin
         Codec.Decode (Writer, Data, Item, Status);
      end Read;
   begin
      Transport.With_Readable_Data (Payload, Read'Access);
   end Decode;

begin
   if not Flyology_Wire.Codecs.Is_Valid (Codec.Descriptor) then
      raise Program_Error with "wire codec descriptor is invalid";
   end if;
end Flyology.Remoting.Codecs.In_Process;
