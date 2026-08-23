with Interfaces;

package body Flyology.Remoting.Protocol.V1.Headers is

   use type Flyology_Wire.Octet;
   use type Flyology_Wire.Octet_Count;
   use type Flyology_Wire.Identities.Schema_Identity_Decode_Status;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   Header_Size : constant Flyology_Wire.Octet_Count := 144;

   subtype Header_Offset is Flyology_Wire.Octet_Offset range 0 .. 143;
   subtype Header_Bytes is Flyology_Wire.Octet_Array (Header_Offset);

   function Encoded_Length return Flyology_Wire.Octet_Count is (Header_Size);

   function Is_Valid (Value : Header) return Boolean is
     (Messages.Is_Valid (Value.Message_Value)
      and then Endpoints.Is_Valid (Value.Source_Slot_Value)
      and then Endpoints.Is_Valid (Value.Source_Generation_Value)
      and then Endpoints.Is_Valid (Value.Destination_Slot_Value)
      and then Endpoints.Is_Valid (Value.Destination_Generation_Value)
      and then Flyology_Wire.Identities.Is_Valid (Value.Writer_Value));

   function Make_Header
     (Payload_Length         : Flyology_Wire.Byte_Count;
      Message                : Messages.Message_ID;
      Correlation            : Messages.Message_ID;
      Source_Slot            : Endpoints.Endpoint_Slot;
      Source_Generation      : Endpoints.Endpoint_Generation;
      Destination_Slot       : Endpoints.Endpoint_Slot;
      Destination_Generation : Endpoints.Endpoint_Generation;
      Writer                 : Flyology_Wire.Identities.Schema_Identity) return Header
   is
      Candidate : constant Header :=
        (Payload_Size                 => Payload_Length,
         Message_Value                => Message,
         Correlation_Value            => Correlation,
         Source_Slot_Value            => Source_Slot,
         Source_Generation_Value      => Source_Generation,
         Destination_Slot_Value       => Destination_Slot,
         Destination_Generation_Value => Destination_Generation,
         Writer_Value                 => Writer);
   begin
      return (if Is_Valid (Candidate) then Candidate else No_Header);
   end Make_Header;

   function Payload_Length (Value : Header) return Flyology_Wire.Byte_Count is
     (Value.Payload_Size);

   function Message (Value : Header) return Messages.Message_ID is
     (Value.Message_Value);

   function Correlation (Value : Header) return Messages.Message_ID is
     (Value.Correlation_Value);

   function Source_Slot (Value : Header) return Endpoints.Endpoint_Slot is
     (Value.Source_Slot_Value);

   function Source_Generation (Value : Header) return Endpoints.Endpoint_Generation is
     (Value.Source_Generation_Value);

   function Destination_Slot (Value : Header) return Endpoints.Endpoint_Slot is
     (Value.Destination_Slot_Value);

   function Destination_Generation (Value : Header) return Endpoints.Endpoint_Generation is
     (Value.Destination_Generation_Value);

   function Writer (Value : Header) return Flyology_Wire.Identities.Schema_Identity is
     (Value.Writer_Value);

   procedure Put_U16
     (Output : in out Header_Bytes;
      Offset : Header_Offset;
      Value  : Interfaces.Unsigned_16)
   is
   begin
      Output (Offset) := Flyology_Wire.Octet (Interfaces.Shift_Right (Value, 8) and 16#FF#);
      Output (Offset + 1) := Flyology_Wire.Octet (Value and 16#FF#);
   end Put_U16;

   procedure Put_U32
     (Output : in out Header_Bytes;
      Offset : Header_Offset;
      Value  : Interfaces.Unsigned_32)
   is
   begin
      for Position in 0 .. 3 loop
         Output (Offset + Flyology_Wire.Octet_Offset (Position)) :=
           Flyology_Wire.Octet
             (Interfaces.Shift_Right (Value, Natural ((3 - Position) * 8)) and 16#FF#);
      end loop;
   end Put_U32;

   procedure Put_U64
     (Output : in out Header_Bytes;
      Offset : Header_Offset;
      Value  : Interfaces.Unsigned_64)
   is
   begin
      for Position in 0 .. 7 loop
         Output (Offset + Flyology_Wire.Octet_Offset (Position)) :=
           Flyology_Wire.Octet
             (Interfaces.Shift_Right (Value, Natural ((7 - Position) * 8)) and 16#FF#);
      end loop;
   end Put_U64;

   procedure Encode
     (Value   : Header;
      Output  : in out Flyology_Wire.Octet_Array;
      Written : out Flyology_Wire.Octet_Count;
      Status  : out Encode_Status)
   is
      Buffer            : Header_Bytes := (others => 0);
      Message_Bytes     : Messages.Message_ID_Bytes;
      Correlation_Bytes : Messages.Message_ID_Bytes;
      Writer_Bytes      : Flyology_Wire.Identities.Schema_Identity_Bytes;
   begin
      Written := 0;

      if not Is_Valid (Value) then
         Status := Invalid_Header;
         return;
      elsif Output'Length < Header_Size then
         Status := Destination_Too_Small;
         return;
      end if;

      Buffer (0) := 16#46#;
      Buffer (1) := 16#4C#;
      Buffer (2) := 16#59#;
      Buffer (3) := 16#52#;
      Put_U16 (Buffer, 4, 1);
      Put_U16 (Buffer, 6, 0);
      Put_U32 (Buffer, 8, 144);
      Put_U64 (Buffer, 12, Interfaces.Unsigned_64 (Value.Payload_Size));
      Put_U32 (Buffer, 20, 0);

      Message_Bytes := Messages.To_Bytes (Value.Message_Value);
      Correlation_Bytes := Messages.To_Bytes (Value.Correlation_Value);
      for Index in Message_Bytes'Range loop
         Buffer (24 + Index) := Message_Bytes (Index);
         Buffer (40 + Index) := Correlation_Bytes (Index);
      end loop;

      Put_U64 (Buffer, 56, Interfaces.Unsigned_64 (Endpoints.To_Word (Value.Source_Slot_Value)));
      Put_U64
        (Buffer, 64, Interfaces.Unsigned_64 (Endpoints.To_Word (Value.Source_Generation_Value)));
      Put_U64
        (Buffer, 72, Interfaces.Unsigned_64 (Endpoints.To_Word (Value.Destination_Slot_Value)));
      Put_U64
        (Buffer, 80, Interfaces.Unsigned_64 (Endpoints.To_Word (Value.Destination_Generation_Value)));

      Writer_Bytes := Flyology_Wire.Identities.To_Bytes (Value.Writer_Value);
      for Index in Writer_Bytes'Range loop
         Buffer (88 + Index) := Writer_Bytes (Index);
      end loop;

      for Index in Buffer'Range loop
         Output (Output'First + Index) := Buffer (Index);
      end loop;

      Written := Header_Size;
      Status := Header_Encoded;
   end Encode;

   function Read_U16
     (Input : Flyology_Wire.Octet_Array;
      Offset : Header_Offset) return Interfaces.Unsigned_16
   is
      Result : Interfaces.Unsigned_16 := 0;
   begin
      for Position in 0 .. 1 loop
         Result :=
           Interfaces.Shift_Left (Result, 8)
           or Interfaces.Unsigned_16 (Input (Input'First + Offset + Flyology_Wire.Octet_Offset (Position)));
      end loop;
      return Result;
   end Read_U16;

   function Read_U32
     (Input : Flyology_Wire.Octet_Array;
      Offset : Header_Offset) return Interfaces.Unsigned_32
   is
      Result : Interfaces.Unsigned_32 := 0;
   begin
      for Position in 0 .. 3 loop
         Result :=
           Interfaces.Shift_Left (Result, 8)
           or Interfaces.Unsigned_32 (Input (Input'First + Offset + Flyology_Wire.Octet_Offset (Position)));
      end loop;
      return Result;
   end Read_U32;

   function Read_U64
     (Input : Flyology_Wire.Octet_Array;
      Offset : Header_Offset) return Interfaces.Unsigned_64
   is
      Result : Interfaces.Unsigned_64 := 0;
   begin
      for Position in 0 .. 7 loop
         Result :=
           Interfaces.Shift_Left (Result, 8)
           or Interfaces.Unsigned_64 (Input (Input'First + Offset + Flyology_Wire.Octet_Offset (Position)));
      end loop;
      return Result;
   end Read_U64;

   procedure Decode
     (Input  : Flyology_Wire.Octet_Array;
      Value  : out Header;
      Status : out Decode_Status)
   is
      Candidate         : Header := No_Header;
      Message_Bytes     : Messages.Message_ID_Bytes;
      Correlation_Bytes : Messages.Message_ID_Bytes;
      Writer_Bytes      : Flyology_Wire.Identities.Schema_Identity_Bytes;
      Writer_Value      : Flyology_Wire.Identities.Schema_Identity;
      Writer_Status     : Flyology_Wire.Identities.Schema_Identity_Decode_Status;
      Source_Slot_Value : Endpoints.Endpoint_Slot;
      Source_Generation_Value : Endpoints.Endpoint_Generation;
      Destination_Slot_Value : Endpoints.Endpoint_Slot;
      Destination_Generation_Value : Endpoints.Endpoint_Generation;
   begin
      Value := No_Header;

      if Input'Length /= Header_Size then
         Status := Invalid_Header_Extent;
         return;
      elsif Input (Input'First) /= 16#46#
        or else Input (Input'First + 1) /= 16#4C#
        or else Input (Input'First + 2) /= 16#59#
        or else Input (Input'First + 3) /= 16#52#
      then
         Status := Invalid_Magic;
         return;
      elsif Read_U16 (Input, 4) /= 1 then
         Status := Unsupported_Major_Version;
         return;
      elsif Read_U16 (Input, 6) /= 0 then
         Status := Unnegotiated_Minor_Version;
         return;
      elsif Read_U32 (Input, 8) /= 144 then
         Status := Invalid_Header_Length;
         return;
      elsif Read_U32 (Input, 20) /= 0 then
         Status := Nonzero_Reserved_Flags;
         return;
      end if;

      for Index in Message_Bytes'Range loop
         Message_Bytes (Index) := Input (Input'First + 24 + Index);
         Correlation_Bytes (Index) := Input (Input'First + 40 + Index);
      end loop;

      Candidate.Message_Value := Messages.Message_ID_From_Bytes (Message_Bytes);
      if not Messages.Is_Valid (Candidate.Message_Value) then
         Status := Invalid_Message_ID;
         return;
      end if;
      Candidate.Correlation_Value := Messages.Message_ID_From_Bytes (Correlation_Bytes);
      Candidate.Payload_Size := Flyology_Wire.Byte_Count (Read_U64 (Input, 12));

      Source_Slot_Value := Endpoints.Slot_From_Word (Endpoints.Endpoint_Word (Read_U64 (Input, 56)));
      Source_Generation_Value :=
        Endpoints.Generation_From_Word (Endpoints.Endpoint_Word (Read_U64 (Input, 64)));
      if not Endpoints.Is_Valid (Source_Slot_Value)
        or else not Endpoints.Is_Valid (Source_Generation_Value)
      then
         Status := Invalid_Source_Endpoint;
         return;
      end if;

      Destination_Slot_Value :=
        Endpoints.Slot_From_Word (Endpoints.Endpoint_Word (Read_U64 (Input, 72)));
      Destination_Generation_Value :=
        Endpoints.Generation_From_Word (Endpoints.Endpoint_Word (Read_U64 (Input, 80)));
      if not Endpoints.Is_Valid (Destination_Slot_Value)
        or else not Endpoints.Is_Valid (Destination_Generation_Value)
      then
         Status := Invalid_Destination_Endpoint;
         return;
      end if;

      for Index in Writer_Bytes'Range loop
         Writer_Bytes (Index) := Input (Input'First + 88 + Index);
      end loop;
      Flyology_Wire.Identities.Schema_Identity_From_Bytes
        (Writer_Bytes, Writer_Value, Writer_Status);
      if Writer_Status /= Flyology_Wire.Identities.Identity_Decoded then
         Status := Invalid_Writer_Schema;
         return;
      end if;

      Candidate.Source_Slot_Value := Source_Slot_Value;
      Candidate.Source_Generation_Value := Source_Generation_Value;
      Candidate.Destination_Slot_Value := Destination_Slot_Value;
      Candidate.Destination_Generation_Value := Destination_Generation_Value;
      Candidate.Writer_Value := Writer_Value;
      if not Is_Valid (Candidate) then
         Status := Invalid_Writer_Schema;
         return;
      end if;

      Value := Candidate;
      Status := Header_Decoded;
   end Decode;

end Flyology.Remoting.Protocol.V1.Headers;
