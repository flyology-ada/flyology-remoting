with Flyology_Wire;

package body Flyology.Remoting.Codecs.Payload_Leases is
   use type Flyology_Wire.Byte_Count;
   use type Flyology_Wire.Codecs.Encode_Status;
   use type Flyology_Wire.Codecs.Measure_Status;
   use type Flyology_Wire.Octet_Count;

   procedure Encode
     (Item    : Codec.Value;
      Payload : in out Writable_Payload;
      Status  : out Flyology_Wire.Codecs.Encode_Status)
   is
      Size           : Flyology_Wire.Byte_Count;
      Measure_Result : Flyology_Wire.Codecs.Measure_Status;
      Invoked        : Boolean := False;

      procedure Write
        (Data : in out Ada.Streams.Stream_Element_Array;
         Length : in out Natural)
      is
         Written : Flyology_Wire.Octet_Count;
      begin
         if Invoked then
            raise Program_Error with "writable lease provider invoked its callback more than once";
         end if;
         Invoked := True;
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
        or else Size > Flyology_Wire.Byte_Count (Capacity (Payload))
      then
         Status := Flyology_Wire.Codecs.Destination_Too_Small;
         return;
      end if;

      With_Writable_Data (Payload, Write'Access);
      if not Invoked then
         raise Program_Error with "writable lease provider did not invoke its callback";
      end if;
   end Encode;

   procedure Decode
     (Writer  : Flyology_Wire.Codecs.Schema_Identity;
      Payload : Received_Payload;
      Item    : out Codec.Value;
      Status  : out Flyology_Wire.Codecs.Decode_Status)
   is
      Invoked : Boolean := False;

      procedure Read (Data : Ada.Streams.Stream_Element_Array) is
      begin
         if Invoked then
            raise Program_Error with "readable lease provider invoked its callback more than once";
         end if;
         Invoked := True;
         Codec.Decode (Writer, Data, Item, Status);
      end Read;
   begin
      With_Readable_Data (Payload, Read'Access);
      if not Invoked then
         raise Program_Error with "readable lease provider did not invoke its callback";
      end if;
   end Decode;

begin
   if not Flyology_Wire.Codecs.Is_Valid (Codec.Descriptor) then
      raise Program_Error with "wire codec descriptor is invalid";
   end if;
end Flyology.Remoting.Codecs.Payload_Leases;
