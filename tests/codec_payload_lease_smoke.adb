with Ada.Streams;
with Flyology.Remoting.Codecs.Payload_Leases;
with Flyology_Wire;
with Flyology_Wire.Codecs;
with Flyology_Wire.Codecs.Contracts;
with Remoting_Test_Codec;
with System;

procedure Codec_Payload_Lease_Smoke is
   package Wire_Codecs renames Flyology_Wire.Codecs;

   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Array;
   use type Flyology_Wire.Octet_Offset;
   use type System.Address;
   use type Wire_Codecs.Decode_Status;
   use type Wire_Codecs.Encode_Status;
   use type Wire_Codecs.Schema_Identity;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Assert;

   subtype Writable_Storage is
     Ada.Streams.Stream_Element_Array (Ada.Streams.Stream_Element_Offset range 17 .. 24);
   subtype Received_Storage is
     Ada.Streams.Stream_Element_Array (Ada.Streams.Stream_Element_Offset range 31 .. 34);

   type Writable_Lease is limited record
      Data           : Writable_Storage := [others => 0];
      Used           : Natural := 2;
      Capacity_Limit : Positive := Writable_Storage'Length;
      Owned          : Boolean := True;
   end record;

   type Received_Lease is limited record
      Data  : Received_Storage := [others => 0];
      Used  : Natural := 1;
      Owned : Boolean := True;
   end record;

   Writable_Borrows : Natural := 0;
   Readable_Borrows : Natural := 0;

   type Borrow_Mode is (Invoke_Once, Skip_Callback, Invoke_Twice);
   Writable_Mode : Borrow_Mode := Invoke_Once;
   Readable_Mode : Borrow_Mode := Invoke_Once;

   function Has_Writable (Payload : Writable_Lease) return Boolean is (Payload.Owned);
   function Has_Received (Payload : Received_Lease) return Boolean is (Payload.Owned);
   function Capacity (Payload : Writable_Lease) return Positive is (Payload.Capacity_Limit);

   procedure With_Writable_Data
     (Payload : in out Writable_Lease;
      Process :
        not null access procedure (Data : in out Ada.Streams.Stream_Element_Array; Length : in out Natural))
   is
      Candidate_Length : Natural := Payload.Used;
   begin
      Writable_Borrows := Writable_Borrows + 1;
      case Writable_Mode is
         when Invoke_Once =>
            Process (Payload.Data, Candidate_Length);
         when Skip_Callback =>
            null;
         when Invoke_Twice =>
            Process (Payload.Data, Candidate_Length);
            Process (Payload.Data, Candidate_Length);
      end case;
      if Candidate_Length > Payload.Capacity_Limit then
         raise Program_Error with "fake lease callback exceeded its declared capacity";
      end if;
      Payload.Used := Candidate_Length;
   end With_Writable_Data;

   procedure With_Readable_Data
     (Payload : Received_Lease;
      Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   is
   begin
      Readable_Borrows := Readable_Borrows + 1;
      case Readable_Mode is
         when Invoke_Once =>
            Process
              (Payload.Data
                 (Payload.Data'First
                  .. Payload.Data'First + Ada.Streams.Stream_Element_Offset (Payload.Used) - 1));
         when Skip_Callback =>
            null;
         when Invoke_Twice =>
            Process
              (Payload.Data
                 (Payload.Data'First
                  .. Payload.Data'First + Ada.Streams.Stream_Element_Offset (Payload.Used) - 1));
            Process
              (Payload.Data
                 (Payload.Data'First
                  .. Payload.Data'First + Ada.Streams.Stream_Element_Offset (Payload.Used) - 1));
      end case;
   end With_Readable_Data;

   package Normal_Adapter is new
     Flyology.Remoting.Codecs.Payload_Leases
       (Writable_Payload   => Writable_Lease,
        Received_Payload   => Received_Lease,
        Has_Writable       => Has_Writable,
        Has_Received       => Has_Received,
        Capacity           => Capacity,
        With_Writable_Data => With_Writable_Data,
        With_Readable_Data => With_Readable_Data,
        Codec              => Remoting_Test_Codec.Contract);

   type Adversarial_Action is
     (Encode_One, Encode_Two, Invalid_Measure, Overflow_Measure, Reported_Failure, Wrong_Written);

   Last_Output_Address : System.Address := System.Null_Address;
   Last_Output_First   : Flyology_Wire.Octet_Offset := 0;
   Last_Input_Address  : System.Address := System.Null_Address;
   Last_Input_First    : Flyology_Wire.Octet_Offset := 0;
   Last_Input_Length   : Flyology_Wire.Octet_Count := 0;
   Raise_During_Decode : Boolean := False;
   Observed_Writer     : Wire_Codecs.Schema_Identity := Remoting_Test_Codec.Contract.Descriptor.Schema;

   function Descriptor return Wire_Codecs.Codec_Descriptor is
     (Remoting_Test_Codec.Contract.Descriptor);

   procedure Measure_Adversarial
     (Item   : Adversarial_Action;
      Size   : out Flyology_Wire.Byte_Count;
      Status : out Wire_Codecs.Measure_Status)
   is
   begin
      case Item is
         when Invalid_Measure =>
            Size := 0;
            Status := Wire_Codecs.Invalid_Value;
         when Overflow_Measure =>
            Size := 0;
            Status := Wire_Codecs.Size_Overflow;
         when Encode_Two =>
            Size := 2;
            Status := Wire_Codecs.Measured;
         when others =>
            Size := 1;
            Status := Wire_Codecs.Measured;
      end case;
   end Measure_Adversarial;

   procedure Encode_Adversarial
     (Item    : Adversarial_Action;
      Output  : in out Flyology_Wire.Octet_Array;
      Written : out Flyology_Wire.Octet_Count;
      Status  : out Wire_Codecs.Encode_Status)
   is
   begin
      Last_Output_Address := Output'Address;
      Last_Output_First := Output'First;
      case Item is
         when Reported_Failure =>
            Written := 0;
            Status := Wire_Codecs.Invalid_Value;
         when Wrong_Written =>
            Output (Output'First) := 16#AB#;
            Written := 0;
            Status := Wire_Codecs.Encoded;
         when Encode_Two =>
            Output (Output'First .. Output'First + 1) := [16#A5#, 16#A6#];
            Written := 2;
            Status := Wire_Codecs.Encoded;
         when others =>
            Output (Output'First) := 16#A5#;
            Written := 1;
            Status := Wire_Codecs.Encoded;
      end case;
   end Encode_Adversarial;

   procedure Decode_Adversarial
     (Writer : Wire_Codecs.Schema_Identity;
      Input  : Flyology_Wire.Octet_Array;
      Item   : out Adversarial_Action;
      Status : out Wire_Codecs.Decode_Status)
   is
   begin
      Last_Input_Address := Input'Address;
      Last_Input_First := Input'First;
      Last_Input_Length := Input'Length;
      Observed_Writer := Writer;
      if Raise_During_Decode then
         raise Constraint_Error with "injected decode callback failure";
      end if;
      Item := Encode_One;
      Status := Wire_Codecs.Decoded;
   end Decode_Adversarial;

   package Adversarial_Contract is new
     Flyology_Wire.Codecs.Contracts
       (Value_Type       => Adversarial_Action,
        Value_Descriptor => Descriptor,
        Measure_Value    => Measure_Adversarial,
        Encode_Value     => Encode_Adversarial,
        Decode_Value     => Decode_Adversarial);

   package Adversarial_Adapter is new
     Flyology.Remoting.Codecs.Payload_Leases
       (Writable_Payload   => Writable_Lease,
        Received_Payload   => Received_Lease,
        Has_Writable       => Has_Writable,
        Has_Received       => Has_Received,
        Capacity           => Capacity,
        With_Writable_Data => With_Writable_Data,
        With_Readable_Data => With_Readable_Data,
        Codec              => Adversarial_Contract);

   function Invalid_Descriptor return Wire_Codecs.Codec_Descriptor is
     ((Schema               =>
         (Family      => [others => 0],
          Fingerprint => [others => 0],
          Revision    => 1,
          Profile     => 1),
       Maximum_Encoded_Size => Wire_Codecs.Unknown_Size));

   package Invalid_Contract is new
     Flyology_Wire.Codecs.Contracts
       (Value_Type       => Adversarial_Action,
        Value_Descriptor => Invalid_Descriptor,
        Measure_Value    => Measure_Adversarial,
        Encode_Value     => Encode_Adversarial,
        Decode_Value     => Decode_Adversarial);

   Writable       : Writable_Lease;
   Received       : Received_Lease;
   Encode_Result  : Wire_Codecs.Encode_Status;
   Decode_Result  : Wire_Codecs.Decode_Status;
   Decoded_Action : Adversarial_Action;
   Before         : Writable_Storage;
   Writer         : Wire_Codecs.Schema_Identity := Remoting_Test_Codec.Contract.Descriptor.Schema;
   Wrong_Rejected : Boolean := False;
   Rejected       : Boolean := False;
   Borrows_Before_Exception : Natural;

   procedure Expect_Writable_Provider_Rejection (Mode : Borrow_Mode; Message : String) is
      Provider_Rejected : Boolean := False;
   begin
      Writable_Mode := Mode;
      Writable.Used := 2;
      begin
         Adversarial_Adapter.Encode (Encode_One, Writable, Encode_Result);
      exception
         when Program_Error =>
            Provider_Rejected := True;
      end;
      Writable_Mode := Invoke_Once;
      Assert (Provider_Rejected and then Writable.Owned and then Writable.Used = 2, Message);
   end Expect_Writable_Provider_Rejection;

   procedure Expect_Readable_Provider_Rejection (Mode : Borrow_Mode; Message : String) is
      Provider_Rejected : Boolean := False;
   begin
      Readable_Mode := Mode;
      begin
         Adversarial_Adapter.Decode (Writer, Received, Decoded_Action, Decode_Result);
      exception
         when Program_Error =>
            Provider_Rejected := True;
      end;
      Readable_Mode := Invoke_Once;
      Assert (Provider_Rejected and then Received.Owned, Message);
   end Expect_Readable_Provider_Rejection;
begin
   Normal_Adapter.Encode ((Number => 300, Valid => True), Writable, Encode_Result);
   Assert
     (Encode_Result = Wire_Codecs.Encoded
      and then Writable.Used = 4
      and then Writable.Data (17 .. 20) = [1, 2, 16#AC#, 2],
      "generic lease adapter did not encode at the arbitrary payload bound");

   Writable.Data := [17 => 9, 18 => 10, others => 0];
   Writable.Used := 2;
   Writable_Borrows := 0;
   Before := Writable.Data;
   Adversarial_Adapter.Encode (Invalid_Measure, Writable, Encode_Result);
   Assert
     (Encode_Result = Wire_Codecs.Invalid_Value
      and then Writable_Borrows = 0
      and then Writable.Used = 2
      and then Writable.Data = Before,
      "invalid measurement borrowed or changed the writable lease");

   Adversarial_Adapter.Encode (Overflow_Measure, Writable, Encode_Result);
   Assert
     (Encode_Result = Wire_Codecs.Size_Overflow
      and then Writable_Borrows = 0
      and then Writable.Used = 2
      and then Writable.Data = Before,
      "overflow measurement borrowed or changed the writable lease");

   Writable.Capacity_Limit := 1;
   Adversarial_Adapter.Encode (Encode_Two, Writable, Encode_Result);
   Assert
     (Encode_Result = Wire_Codecs.Destination_Too_Small
      and then Writable_Borrows = 0
      and then Writable.Used = 2
      and then Writable.Data = Before,
      "short capacity borrowed or changed the writable lease");

   Writable.Capacity_Limit := Writable_Storage'Length;
   Adversarial_Adapter.Encode (Reported_Failure, Writable, Encode_Result);
   Assert
     (Encode_Result = Wire_Codecs.Invalid_Value
      and then Writable_Borrows = 1
      and then Writable.Used = 2
      and then Writable.Data = Before,
      "reported encode failure changed committed payload state");

   Adversarial_Adapter.Encode (Encode_One, Writable, Encode_Result);
   Assert
     (Encode_Result = Wire_Codecs.Encoded
      and then Writable_Borrows = 2
      and then Writable.Used = 1
      and then Writable.Data (Writable.Data'First) = 16#A5#
      and then Last_Output_Address = Writable.Data'Address
      and then Last_Output_First = Writable.Data'First,
      "generic adapter copied storage, changed its bound, or failed to commit exact length");

   Writable.Used := 2;
   begin
      Adversarial_Adapter.Encode (Wrong_Written, Writable, Encode_Result);
   exception
      when Program_Error =>
         Wrong_Rejected := True;
   end;
   Assert
     (Wrong_Rejected and then Writable.Owned and then Writable.Used = 2,
      "wrong successful encode length committed or released the writable lease");
   Expect_Writable_Provider_Rejection
     (Skip_Callback, "missing writable callback was accepted or changed lease state");
   Expect_Writable_Provider_Rejection
     (Invoke_Twice, "duplicate writable callback was accepted or committed lease state");

   Writer.Fingerprint (Writer.Fingerprint'Last) := 16#7E#;
   Readable_Borrows := 0;
   Adversarial_Adapter.Decode (Writer, Received, Decoded_Action, Decode_Result);
   Assert
     (Decode_Result = Wire_Codecs.Decoded
      and then Decoded_Action = Encode_One
      and then Observed_Writer = Writer
      and then Readable_Borrows = 1
      and then Last_Input_Address = Received.Data'Address
      and then Last_Input_First = Received.Data'First
      and then Last_Input_Length = Flyology_Wire.Octet_Count (Received.Used)
      and then Received.Owned,
      "decode changed the writer, payload storage, bounds, extent, or lease ownership");
   Expect_Readable_Provider_Rejection
     (Skip_Callback, "missing readable callback was accepted or released the lease");
   Expect_Readable_Provider_Rejection
     (Invoke_Twice, "duplicate readable callback was accepted or released the lease");

   Borrows_Before_Exception := Readable_Borrows;
   Raise_During_Decode := True;
   begin
      Adversarial_Adapter.Decode (Writer, Received, Decoded_Action, Decode_Result);
      raise Program_Error with "decode callback exception did not propagate";
   exception
      when Constraint_Error =>
         null;
   end;
   Assert
     (Readable_Borrows = Borrows_Before_Exception + 1 and then Received.Owned,
      "decode callback unwinding released or lost the received lease");

   begin
      declare
         package Invalid_Adapter is new
           Flyology.Remoting.Codecs.Payload_Leases
             (Writable_Payload   => Writable_Lease,
              Received_Payload   => Received_Lease,
              Has_Writable       => Has_Writable,
              Has_Received       => Has_Received,
              Capacity           => Capacity,
              With_Writable_Data => With_Writable_Data,
              With_Readable_Data => With_Readable_Data,
              Codec              => Invalid_Contract);
      begin
         Invalid_Adapter.Encode (Encode_One, Writable, Encode_Result);
      end;
   exception
      when Program_Error =>
         Rejected := True;
   end;
   Assert (Rejected, "invalid codec descriptor was accepted during adapter elaboration");
end Codec_Payload_Lease_Smoke;
