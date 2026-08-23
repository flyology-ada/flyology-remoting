with Flyology_Wire.Profiles.Tagged_Profile;
with Flyology_Wire.Sizes;

package body Remoting_Test_Codec is
   package Profile renames Flyology_Wire.Profiles.Tagged_Profile;

   use type Flyology_Wire.Codecs.Measure_Status;
   use type Flyology_Wire.Codecs.Schema_Identity;
   use type Flyology_Wire.Octet_Count;
   use type Flyology_Wire.Sizes.Arithmetic_Status;
   use type Profile.Cursor_Status;
   use type Profile.Field_Tag;
   use type Profile.Read_Status;
   use type Profile.Write_Status;

   procedure Measure
     (Item   : Value;
      Size   : out Flyology_Wire.Byte_Count;
      Status : out Flyology_Wire.Codecs.Measure_Status)
   is
      Arithmetic : Flyology_Wire.Sizes.Arithmetic_Status;
   begin
      Size := 0;
      if not Item.Valid then
         Status := Flyology_Wire.Codecs.Invalid_Value;
         return;
      end if;

      Profile.Measure_Field
        (Tag          => 1,
         Value_Length => Flyology_Wire.Byte_Count (Profile.Unsigned_Size (Item.Number)),
         Size         => Size,
         Status       => Arithmetic);
      if Arithmetic = Flyology_Wire.Sizes.Computed then
         Status := Flyology_Wire.Codecs.Measured;
      else
         Status := Flyology_Wire.Codecs.Size_Overflow;
      end if;
   end Measure;

   procedure Encode
     (Item    : Value;
      Output  : in out Flyology_Wire.Octet_Array;
      Written : out Flyology_Wire.Octet_Count;
      Status  : out Flyology_Wire.Codecs.Encode_Status)
   is
      Size           : Flyology_Wire.Byte_Count;
      Measure_Result : Flyology_Wire.Codecs.Measure_Status;
      Outer          : Profile.Write_Cursor;
      Inner          : Profile.Write_Cursor;
      Previous       : Profile.Tag_Number := Profile.No_Tag;
      Region         : Profile.Extent;
      Cursor_Result  : Profile.Cursor_Status;
      Write_Result   : Profile.Write_Status;
   begin
      Written := 0;
      Measure (Item, Size, Measure_Result);
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
        or else Flyology_Wire.To_Octet_Count (Size) > Output'Length
      then
         Status := Flyology_Wire.Codecs.Destination_Too_Small;
         return;
      end if;

      Region := (Start => 0, Length => Flyology_Wire.To_Octet_Count (Size));
      Profile.Initialize (Outer, Output, Region, Cursor_Result);
      if Cursor_Result /= Profile.Cursor_Ready then
         raise Program_Error with "measured Profile 1 output extent was invalid";
      end if;
      Profile.Write_Field_Header
        (Output       => Output,
         Cursor       => Outer,
         Previous     => Previous,
         Tag          => 1,
         Value_Length => Flyology_Wire.Byte_Count (Profile.Unsigned_Size (Item.Number)),
         Value        => Region,
         Status       => Write_Result);
      if Write_Result /= Profile.Wrote then
         raise Program_Error with "measured Profile 1 field header did not fit";
      end if;

      Profile.Initialize (Inner, Output, Region, Cursor_Result);
      if Cursor_Result /= Profile.Cursor_Ready then
         raise Program_Error with "measured Profile 1 field extent was invalid";
      end if;
      Profile.Write_Unsigned (Output, Inner, Item.Number, Write_Result);
      if Write_Result /= Profile.Wrote or else not Profile.At_End (Inner) then
         raise Program_Error with "measured Profile 1 value did not fill its extent";
      end if;

      Written := Profile.Consumed (Outer);
      if Written /= Flyology_Wire.To_Octet_Count (Size) or else not Profile.At_End (Outer) then
         raise Program_Error with "Profile 1 encoder disagreed with exact measurement";
      end if;
      Status := Flyology_Wire.Codecs.Encoded;
   end Encode;

   function Decode_Status_For
     (Status : Profile.Read_Status) return Flyology_Wire.Codecs.Decode_Status
   is
   begin
      case Status is
         when Profile.Truncated | Profile.Extent_Outside_Container =>
            return Flyology_Wire.Codecs.Malformed;
         when Profile.Value_Overflow
            | Profile.Noncanonical
            | Profile.Invalid_Boolean
            | Profile.Invalid_Tag
            | Profile.Tag_Order_Error =>
            return Flyology_Wire.Codecs.Noncanonical;
         when Profile.Read =>
            raise Program_Error with "successful Profile 1 read was mapped as a failure";
      end case;
   end Decode_Status_For;

   procedure Decode
     (Writer : Flyology_Wire.Codecs.Schema_Identity;
      Input  : Flyology_Wire.Octet_Array;
      Item   : out Value;
      Status : out Flyology_Wire.Codecs.Decode_Status)
   is
      Candidate      : Value := (Number => 0, Valid => False);
      Outer          : Profile.Read_Cursor;
      Inner          : Profile.Read_Cursor;
      Previous       : Profile.Tag_Number := Profile.No_Tag;
      Tag            : Profile.Field_Tag;
      Region         : Profile.Extent;
      Cursor_Result  : Profile.Cursor_Status;
      Read_Result    : Profile.Read_Status;
   begin
      Item := Candidate;
      if Writer /= Descriptor.Schema then
         Status := Flyology_Wire.Codecs.Incompatible;
         return;
      end if;

      Profile.Initialize (Outer, Input);
      Profile.Read_Field_Header (Input, Outer, Previous, Tag, Region, Read_Result);
      if Read_Result /= Profile.Read then
         Status := Decode_Status_For (Read_Result);
         return;
      elsif Tag /= 1 or else not Profile.At_End (Outer) then
         Status := Flyology_Wire.Codecs.Malformed;
         return;
      end if;

      Profile.Initialize (Inner, Input, Region, Cursor_Result);
      if Cursor_Result /= Profile.Cursor_Ready then
         Status := Flyology_Wire.Codecs.Malformed;
         return;
      end if;
      Profile.Read_Unsigned (Input, Inner, Candidate.Number, Read_Result);
      if Read_Result /= Profile.Read then
         Status := Decode_Status_For (Read_Result);
         return;
      elsif not Profile.At_End (Inner) then
         Status := Flyology_Wire.Codecs.Noncanonical;
         return;
      end if;

      Candidate.Valid := True;
      Item := Candidate;
      Status := Flyology_Wire.Codecs.Decoded;
   end Decode;

end Remoting_Test_Codec;
