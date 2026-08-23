with Flyology.Remoting.Endpoints;
with Flyology.Remoting.Messages;
with Flyology.Remoting.Protocol.V1.Headers;
with Flyology_Wire;
with Flyology_Wire.Identities;

procedure Header_Codec_Smoke is
   package Endpoints renames Flyology.Remoting.Endpoints;
   package Headers renames Flyology.Remoting.Protocol.V1.Headers;
   package Messages renames Flyology.Remoting.Messages;
   package Wire_Identities renames Flyology_Wire.Identities;

   use type Endpoints.Endpoint_Generation;
   use type Endpoints.Endpoint_Slot;
   use type Flyology_Wire.Byte_Count;
   use type Flyology_Wire.Octet;
   use type Flyology_Wire.Octet_Count;
   use type Headers.Decode_Status;
   use type Headers.Encode_Status;
   use type Headers.Header;
   use type Messages.Message_ID;
   use type Wire_Identities.Schema_Identity;
   use type Wire_Identities.Schema_Identity_Decode_Status;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Assert;

   Message_Bytes : constant Messages.Message_ID_Bytes :=
     [16#81#, 16#82#, 16#83#, 16#84#, 16#85#, 16#86#, 16#87#, 16#88#,
      16#89#, 16#8A#, 16#8B#, 16#8C#, 16#8D#, 16#8E#, 16#8F#, 16#90#];
   Correlation_Bytes : constant Messages.Message_ID_Bytes :=
     [16#A1#, 16#A2#, 16#A3#, 16#A4#, 16#A5#, 16#A6#, 16#A7#, 16#A8#,
      16#A9#, 16#AA#, 16#AB#, 16#AC#, 16#AD#, 16#AE#, 16#AF#, 16#B0#];
   Writer_Bytes : constant Wire_Identities.Schema_Identity_Bytes :=
     [16#01#, 16#02#, 16#03#, 16#04#, 16#05#, 16#06#, 16#07#, 16#08#,
      16#09#, 16#0A#, 16#0B#, 16#0C#, 16#0D#, 16#0E#, 16#0F#, 16#10#,
      16#21#, 16#22#, 16#23#, 16#24#, 16#25#, 16#26#, 16#27#, 16#28#,
      16#29#, 16#2A#, 16#2B#, 16#2C#, 16#2D#, 16#2E#, 16#2F#, 16#30#,
      16#31#, 16#32#, 16#33#, 16#34#, 16#35#, 16#36#, 16#37#, 16#38#,
      16#39#, 16#3A#, 16#3B#, 16#3C#, 16#3D#, 16#3E#, 16#3F#, 16#40#,
      16#01#, 16#02#, 16#03#, 16#04#, 16#00#, 16#00#, 16#00#, 16#01#];

   subtype Header_Array is Flyology_Wire.Octet_Array (0 .. 143);

   Expected : constant Header_Array :=
     [16#46#, 16#4C#, 16#59#, 16#52#, 16#00#, 16#01#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#00#, 16#90#, 16#41#, 16#42#, 16#43#, 16#44#,
      16#45#, 16#46#, 16#47#, 16#48#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#81#, 16#82#, 16#83#, 16#84#, 16#85#, 16#86#, 16#87#, 16#88#,
      16#89#, 16#8A#, 16#8B#, 16#8C#, 16#8D#, 16#8E#, 16#8F#, 16#90#,
      16#A1#, 16#A2#, 16#A3#, 16#A4#, 16#A5#, 16#A6#, 16#A7#, 16#A8#,
      16#A9#, 16#AA#, 16#AB#, 16#AC#, 16#AD#, 16#AE#, 16#AF#, 16#B0#,
      16#01#, 16#02#, 16#03#, 16#04#, 16#05#, 16#06#, 16#07#, 16#08#,
      16#11#, 16#12#, 16#13#, 16#14#, 16#15#, 16#16#, 16#17#, 16#18#,
      16#21#, 16#22#, 16#23#, 16#24#, 16#25#, 16#26#, 16#27#, 16#28#,
      16#31#, 16#32#, 16#33#, 16#34#, 16#35#, 16#36#, 16#37#, 16#38#,
      16#01#, 16#02#, 16#03#, 16#04#, 16#05#, 16#06#, 16#07#, 16#08#,
      16#09#, 16#0A#, 16#0B#, 16#0C#, 16#0D#, 16#0E#, 16#0F#, 16#10#,
      16#21#, 16#22#, 16#23#, 16#24#, 16#25#, 16#26#, 16#27#, 16#28#,
      16#29#, 16#2A#, 16#2B#, 16#2C#, 16#2D#, 16#2E#, 16#2F#, 16#30#,
      16#31#, 16#32#, 16#33#, 16#34#, 16#35#, 16#36#, 16#37#, 16#38#,
      16#39#, 16#3A#, 16#3B#, 16#3C#, 16#3D#, 16#3E#, 16#3F#, 16#40#,
      16#01#, 16#02#, 16#03#, 16#04#, 16#00#, 16#00#, 16#00#, 16#01#];

   procedure Copy_Expected (Target : out Flyology_Wire.Octet_Array) is
   begin
      Assert (Target'Length >= Headers.Encoded_Length, "test target is shorter than one header");
      for Index in Expected'Range loop
         Target (Target'First + Index) := Expected (Index);
      end loop;
   end Copy_Expected;

   Writer        : Wire_Identities.Schema_Identity;
   Writer_Status : Wire_Identities.Schema_Identity_Decode_Status;
begin
   Wire_Identities.Schema_Identity_From_Bytes (Writer_Bytes, Writer, Writer_Status);
   Assert (Writer_Status = Wire_Identities.Identity_Decoded, "test writer identity was invalid");

   declare
      Message_ID     : constant Messages.Message_ID := Messages.Message_ID_From_Bytes (Message_Bytes);
      Correlation_ID : constant Messages.Message_ID := Messages.Message_ID_From_Bytes (Correlation_Bytes);
      Value          : constant Headers.Header :=
        Headers.Make_Header
          (Payload_Length          => 16#4142_4344_4546_4748#,
           Message                 => Message_ID,
           Correlation             => Correlation_ID,
           Source_Slot             => Endpoints.Slot_From_Word (16#0102_0304_0506_0708#),
           Source_Generation       => Endpoints.Generation_From_Word (16#1112_1314_1516_1718#),
           Destination_Slot        => Endpoints.Slot_From_Word (16#2122_2324_2526_2728#),
           Destination_Generation  => Endpoints.Generation_From_Word (16#3132_3334_3536_3738#),
           Writer                  => Writer);

      procedure Assert_Decoded (Item : Headers.Header; Context : String) is
      begin
         Assert (Headers.Is_Valid (Item), Context & ": decoded header was invalid");
         Assert
           (Headers.Payload_Length (Item) = 16#4142_4344_4546_4748#,
            Context & ": payload length changed");
         Assert (Headers.Message (Item) = Message_ID, Context & ": message identity changed");
         Assert (Headers.Correlation (Item) = Correlation_ID, Context & ": correlation changed");
         Assert
           (Headers.Source_Slot (Item) = Endpoints.Slot_From_Word (16#0102_0304_0506_0708#),
            Context & ": source slot changed");
         Assert
           (Headers.Source_Generation (Item)
              = Endpoints.Generation_From_Word (16#1112_1314_1516_1718#),
            Context & ": source generation changed");
         Assert
           (Headers.Destination_Slot (Item) = Endpoints.Slot_From_Word (16#2122_2324_2526_2728#),
            Context & ": destination slot changed");
         Assert
           (Headers.Destination_Generation (Item)
              = Endpoints.Generation_From_Word (16#3132_3334_3536_3738#),
            Context & ": destination generation changed");
         Assert (Headers.Writer (Item) = Writer, Context & ": writer identity changed");
      end Assert_Decoded;

      procedure Expect_Corruption
        (Offset   : Flyology_Wire.Octet_Offset;
         Octet    : Flyology_Wire.Octet;
         Expected_Status : Headers.Decode_Status)
      is
         Input    : Header_Array := Expected;
         Observed : Headers.Header := Value;
         Status   : Headers.Decode_Status;
      begin
         Input (Offset) := Octet;
         Headers.Decode (Input, Observed, Status);
         Assert (Status = Expected_Status, "single-byte corruption had the wrong status");
         Assert (Observed = Headers.No_Header, "failed decode published a partial header");
      end Expect_Corruption;

      procedure Expect_Zero_Range
        (First, Last    : Flyology_Wire.Octet_Offset;
         Expected_Status : Headers.Decode_Status)
      is
         Input    : Header_Array := Expected;
         Observed : Headers.Header := Value;
         Status   : Headers.Decode_Status;
      begin
         Input (First .. Last) := [others => 0];
         Headers.Decode (Input, Observed, Status);
         Assert (Status = Expected_Status, "zeroed field had the wrong status");
         Assert (Observed = Headers.No_Header, "zeroed-field failure published a partial header");
      end Expect_Zero_Range;

      procedure Roundtrip
        (Size        : Flyology_Wire.Byte_Count;
         Correlation : Messages.Message_ID)
      is
         Candidate : constant Headers.Header :=
           Headers.Make_Header
             (Payload_Length          => Size,
              Message                 => Message_ID,
              Correlation             => Correlation,
              Source_Slot             => Endpoints.Slot_From_Word (1),
              Source_Generation       => Endpoints.Generation_From_Word (2),
              Destination_Slot        => Endpoints.Slot_From_Word (3),
              Destination_Generation  => Endpoints.Generation_From_Word (4),
              Writer                  => Writer);
         Bytes         : Header_Array := [others => 0];
         Decoded       : Headers.Header;
         Encode_Result : Headers.Encode_Status;
         Decode_Result : Headers.Decode_Status;
         Written       : Flyology_Wire.Octet_Count;
      begin
         Headers.Encode (Candidate, Bytes, Written, Encode_Result);
         Assert
           (Encode_Result = Headers.Header_Encoded and then Written = Headers.Encoded_Length,
            "boundary payload header did not encode");
         Headers.Decode (Bytes, Decoded, Decode_Result);
         Assert (Decode_Result = Headers.Header_Decoded, "boundary payload header did not decode");
         Assert (Headers.Payload_Length (Decoded) = Size, "boundary payload length changed");
         Assert (Headers.Correlation (Decoded) = Correlation, "boundary correlation changed");
      end Roundtrip;

      procedure Expect_Invalid_Constructor
        (Candidate_Message          : Messages.Message_ID;
         Candidate_Source_Slot      : Endpoints.Endpoint_Slot;
         Candidate_Source_Generation : Endpoints.Endpoint_Generation;
         Candidate_Destination_Slot : Endpoints.Endpoint_Slot;
         Candidate_Destination_Generation : Endpoints.Endpoint_Generation;
         Candidate_Writer           : Wire_Identities.Schema_Identity;
         Context                    : String)
      is
         Candidate : constant Headers.Header :=
           Headers.Make_Header
             (0,
              Candidate_Message,
              Messages.No_Message_ID,
              Candidate_Source_Slot,
              Candidate_Source_Generation,
              Candidate_Destination_Slot,
              Candidate_Destination_Generation,
              Candidate_Writer);
      begin
         Assert (Candidate = Headers.No_Header, Context & " constructed a header");
      end Expect_Invalid_Constructor;

      type Fault_Kind is
        (Bad_Magic,
         Bad_Major,
         Bad_Minor,
         Bad_Header_Length,
         Bad_Flags,
         Bad_Message,
         Bad_Source,
         Bad_Destination,
         Bad_Writer);

      procedure Apply_Fault (Input : in out Header_Array; Fault : Fault_Kind) is
      begin
         case Fault is
            when Bad_Magic =>
               Input (0) := 0;
            when Bad_Major =>
               Input (5) := 2;
            when Bad_Minor =>
               Input (7) := 1;
            when Bad_Header_Length =>
               Input (11) := 16#8F#;
            when Bad_Flags =>
               Input (23) := 1;
            when Bad_Message =>
               Input (24 .. 39) := [others => 0];
            when Bad_Source =>
               Input (56 .. 63) := [others => 0];
            when Bad_Destination =>
               Input (72 .. 79) := [others => 0];
            when Bad_Writer =>
               Input (88 .. 103) := [others => 0];
         end case;
      end Apply_Fault;

      procedure Expect_Precedence
        (Earlier         : Fault_Kind;
         Later           : Fault_Kind;
         Expected_Status : Headers.Decode_Status)
      is
         Input    : Header_Array := Expected;
         Observed : Headers.Header := Value;
         Status   : Headers.Decode_Status;
      begin
         Apply_Fault (Input, Later);
         Apply_Fault (Input, Earlier);
         Headers.Decode (Input, Observed, Status);
         Assert (Status = Expected_Status, "multiple faults changed validation precedence");
         Assert (Observed = Headers.No_Header, "multiple faults published a header");
      end Expect_Precedence;
   begin
      Assert (Headers.Encoded_Length = 144, "version-one encoded header length changed");
      Assert (Messages.Is_Valid (Message_ID), "nonzero message identity was invalid");
      Assert (not Messages.Is_Valid (Messages.No_Message_ID), "zero message identity was valid");
      Assert (Headers.Is_Valid (Value), "valid semantic header was rejected");

      declare
         Output  : Flyology_Wire.Octet_Array (-10 .. 140) := [others => 16#EE#];
         Written : Flyology_Wire.Octet_Count;
         Status  : Headers.Encode_Status;
         Decoded : Headers.Header;
         Decode_Result : Headers.Decode_Status;
      begin
         Headers.Encode (Value, Output, Written, Status);
         Assert
           (Status = Headers.Header_Encoded and then Written = Headers.Encoded_Length,
            "valid header did not encode");
         for Index in Expected'Range loop
            Assert (Output (Output'First + Index) = Expected (Index), "golden header byte changed");
         end loop;
         for Index in Output'First + 144 .. Output'Last loop
            Assert (Output (Index) = 16#EE#, "encode modified destination tail");
         end loop;

         Headers.Decode (Output (Output'First .. Output'First + 143), Decoded, Decode_Result);
         Assert (Decode_Result = Headers.Header_Decoded, "negative-bound header did not decode");
         Assert_Decoded (Decoded, "negative-bound header");
      end;

      declare
         First   : constant Flyology_Wire.Octet_Offset := Flyology_Wire.Octet_Offset'Last - 143;
         Input   : Flyology_Wire.Octet_Array (First .. Flyology_Wire.Octet_Offset'Last) :=
           [others => 16#EE#];
         Decoded : Headers.Header;
         Decode_Result : Headers.Decode_Status;
         Encode_Result : Headers.Encode_Status;
         Written : Flyology_Wire.Octet_Count;
      begin
         Headers.Encode (Value, Input, Written, Encode_Result);
         Assert
           (Encode_Result = Headers.Header_Encoded and then Written = Headers.Encoded_Length,
            "high-bound header did not encode");
         for Index in Expected'Range loop
            Assert (Input (Input'First + Index) = Expected (Index), "high-bound encode byte changed");
         end loop;
         Headers.Decode (Input, Decoded, Decode_Result);
         Assert (Decode_Result = Headers.Header_Decoded, "high-bound header did not decode");
         Assert_Decoded (Decoded, "high-bound header");
      end;

      Roundtrip (0, Messages.No_Message_ID);
      Roundtrip (Flyology_Wire.Byte_Count'Last, Correlation_ID);

      declare
         Small    : Flyology_Wire.Octet_Array (5 .. 147) := [others => 16#CC#];
         Invalid  : Header_Array := [others => 16#DD#];
         Written  : Flyology_Wire.Octet_Count;
         Status   : Headers.Encode_Status;
      begin
         Headers.Encode (Value, Small, Written, Status);
         Assert
           (Status = Headers.Destination_Too_Small and then Written = 0,
            "short encode destination had the wrong result");
         for Octet of Small loop
            Assert (Octet = 16#CC#, "failed short encode modified output");
         end loop;

         Headers.Encode (Headers.No_Header, Small, Written, Status);
         Assert
           (Status = Headers.Invalid_Header and then Written = 0,
            "invalid short encode changed validation precedence");
         for Octet of Small loop
            Assert (Octet = 16#CC#, "invalid short encode modified output");
         end loop;

         Headers.Encode (Headers.No_Header, Invalid, Written, Status);
         Assert
           (Status = Headers.Invalid_Header and then Written = 0,
            "invalid header encode had the wrong result");
         for Octet of Invalid loop
            Assert (Octet = 16#DD#, "invalid header encode modified output");
         end loop;
      end;

      declare
         Short    : Flyology_Wire.Octet_Array (0 .. 142);
         Long     : Flyology_Wire.Octet_Array (0 .. 144) := [others => 0];
         Observed : Headers.Header := Value;
         Status   : Headers.Decode_Status;
      begin
         for Index in Short'Range loop
            Short (Index) := Expected (Index);
         end loop;
         Headers.Decode (Short, Observed, Status);
         Assert (Status = Headers.Invalid_Header_Extent, "short header extent was accepted");
         Assert (Observed = Headers.No_Header, "short extent published a header");

         Copy_Expected (Long);
         Long (0) := 0;
         Headers.Decode (Long, Observed, Status);
         Assert (Status = Headers.Invalid_Header_Extent, "extent did not precede invalid magic");
         Assert (Observed = Headers.No_Header, "long extent published a header");
      end;

      Expect_Corruption (0, 0, Headers.Invalid_Magic);
      Expect_Corruption (5, 2, Headers.Unsupported_Major_Version);
      Expect_Corruption (7, 1, Headers.Unnegotiated_Minor_Version);
      Expect_Corruption (11, 16#8F#, Headers.Invalid_Header_Length);
      Expect_Corruption (23, 1, Headers.Nonzero_Reserved_Flags);
      Expect_Zero_Range (24, 39, Headers.Invalid_Message_ID);
      Expect_Zero_Range (56, 63, Headers.Invalid_Source_Endpoint);
      Expect_Zero_Range (64, 71, Headers.Invalid_Source_Endpoint);
      Expect_Zero_Range (72, 79, Headers.Invalid_Destination_Endpoint);
      Expect_Zero_Range (80, 87, Headers.Invalid_Destination_Endpoint);
      Expect_Zero_Range (88, 103, Headers.Invalid_Writer_Schema);
      Expect_Zero_Range (104, 135, Headers.Invalid_Writer_Schema);
      Expect_Zero_Range (136, 139, Headers.Invalid_Writer_Schema);
      Expect_Zero_Range (140, 143, Headers.Invalid_Writer_Schema);

      Expect_Precedence (Bad_Magic, Bad_Major, Headers.Invalid_Magic);
      Expect_Precedence (Bad_Major, Bad_Minor, Headers.Unsupported_Major_Version);
      Expect_Precedence (Bad_Minor, Bad_Header_Length, Headers.Unnegotiated_Minor_Version);
      Expect_Precedence (Bad_Header_Length, Bad_Flags, Headers.Invalid_Header_Length);
      Expect_Precedence (Bad_Flags, Bad_Message, Headers.Nonzero_Reserved_Flags);
      Expect_Precedence (Bad_Message, Bad_Source, Headers.Invalid_Message_ID);
      Expect_Precedence (Bad_Source, Bad_Destination, Headers.Invalid_Source_Endpoint);
      Expect_Precedence (Bad_Destination, Bad_Writer, Headers.Invalid_Destination_Endpoint);

      declare
         Invalid_Family_Writer : constant Wire_Identities.Schema_Identity :=
           (Family      => [others => 0],
            Fingerprint => Writer.Fingerprint,
            Revision    => Writer.Revision,
            Profile     => Writer.Profile);
         Invalid_Fingerprint_Writer : constant Wire_Identities.Schema_Identity :=
           (Family      => Writer.Family,
            Fingerprint => [others => 0],
            Revision    => Writer.Revision,
            Profile     => Writer.Profile);
      begin
         Expect_Invalid_Constructor
           (Messages.No_Message_ID,
            Endpoints.Slot_From_Word (1),
            Endpoints.Generation_From_Word (2),
            Endpoints.Slot_From_Word (3),
            Endpoints.Generation_From_Word (4),
            Writer,
            "invalid message identity");
         Expect_Invalid_Constructor
           (Message_ID,
            Endpoints.No_Endpoint_Slot,
            Endpoints.Generation_From_Word (2),
            Endpoints.Slot_From_Word (3),
            Endpoints.Generation_From_Word (4),
            Writer,
            "invalid source slot");
         Expect_Invalid_Constructor
           (Message_ID,
            Endpoints.Slot_From_Word (1),
            Endpoints.No_Endpoint_Generation,
            Endpoints.Slot_From_Word (3),
            Endpoints.Generation_From_Word (4),
            Writer,
            "invalid source generation");
         Expect_Invalid_Constructor
           (Message_ID,
            Endpoints.Slot_From_Word (1),
            Endpoints.Generation_From_Word (2),
            Endpoints.No_Endpoint_Slot,
            Endpoints.Generation_From_Word (4),
            Writer,
            "invalid destination slot");
         Expect_Invalid_Constructor
           (Message_ID,
            Endpoints.Slot_From_Word (1),
            Endpoints.Generation_From_Word (2),
            Endpoints.Slot_From_Word (3),
            Endpoints.No_Endpoint_Generation,
            Writer,
            "invalid destination generation");
         Expect_Invalid_Constructor
           (Message_ID,
            Endpoints.Slot_From_Word (1),
            Endpoints.Generation_From_Word (2),
            Endpoints.Slot_From_Word (3),
            Endpoints.Generation_From_Word (4),
            Invalid_Family_Writer,
            "invalid writer family");
         Expect_Invalid_Constructor
           (Message_ID,
            Endpoints.Slot_From_Word (1),
            Endpoints.Generation_From_Word (2),
            Endpoints.Slot_From_Word (3),
            Endpoints.Generation_From_Word (4),
            Invalid_Fingerprint_Writer,
            "invalid writer fingerprint");
      end;
   end;
end Header_Codec_Smoke;
