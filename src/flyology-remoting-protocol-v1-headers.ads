with Flyology.Remoting.Endpoints;
with Flyology.Remoting.Messages;
with Flyology_Wire;
with Flyology_Wire.Identities;

--  Encodes and decodes only the fixed version-one header. Session route
--  reconstruction, complete-message extents, payload leases, and I/O belong
--  to higher layers.
package Flyology.Remoting.Protocol.V1.Headers
  with Preelaborate
is
   type Header is private;

   No_Header : constant Header;

   --  Return the exact encoded header size accepted by version one.
   function Encoded_Length return Flyology_Wire.Octet_Count;

   --  Construct one semantic header. Invalid components return No_Header.
   function Make_Header
     (Payload_Length         : Flyology_Wire.Byte_Count;
      Message                : Messages.Message_ID;
      Correlation            : Messages.Message_ID;
      Source_Slot            : Endpoints.Endpoint_Slot;
      Source_Generation      : Endpoints.Endpoint_Generation;
      Destination_Slot       : Endpoints.Endpoint_Slot;
      Destination_Generation : Endpoints.Endpoint_Generation;
      Writer                 : Flyology_Wire.Identities.Schema_Identity) return Header;

   function Is_Valid (Value : Header) return Boolean;

   function Payload_Length (Value : Header) return Flyology_Wire.Byte_Count
   with Pre => Is_Valid (Value);

   function Message (Value : Header) return Messages.Message_ID
   with Pre => Is_Valid (Value);

   function Correlation (Value : Header) return Messages.Message_ID
   with Pre => Is_Valid (Value);

   function Source_Slot (Value : Header) return Endpoints.Endpoint_Slot
   with Pre => Is_Valid (Value);

   function Source_Generation (Value : Header) return Endpoints.Endpoint_Generation
   with Pre => Is_Valid (Value);

   function Destination_Slot (Value : Header) return Endpoints.Endpoint_Slot
   with Pre => Is_Valid (Value);

   function Destination_Generation (Value : Header) return Endpoints.Endpoint_Generation
   with Pre => Is_Valid (Value);

   function Writer (Value : Header) return Flyology_Wire.Identities.Schema_Identity
   with Pre => Is_Valid (Value);

   --  Invalid_Header is checked before destination capacity.
   type Encode_Status is (Header_Encoded, Invalid_Header, Destination_Too_Small);

   --  Encode into the first Encoded_Length octets relative to Output'First.
   --  A reported failure publishes Written = 0 and leaves all Output bytes
   --  unchanged.
   procedure Encode
     (Value   : Header;
      Output  : in out Flyology_Wire.Octet_Array;
      Written : out Flyology_Wire.Octet_Count;
      Status  : out Encode_Status);

   --  Values after Header_Decoded are also the validation precedence when an
   --  input contains more than one fault.
   type Decode_Status is
     (Header_Decoded,
      Invalid_Header_Extent,
      Invalid_Magic,
      Unsupported_Major_Version,
      Unnegotiated_Minor_Version,
      Invalid_Header_Length,
      Nonzero_Reserved_Flags,
      Invalid_Message_ID,
      Invalid_Source_Endpoint,
      Invalid_Destination_Endpoint,
      Invalid_Writer_Schema);

   --  Decode one exact header slice. Failure publishes No_Header.
   procedure Decode
     (Input  : Flyology_Wire.Octet_Array;
      Value  : out Header;
      Status : out Decode_Status);

private
   Invalid_Writer : constant Flyology_Wire.Identities.Schema_Identity :=
     (Family      => (others => 0),
      Fingerprint => (others => 0),
      Revision    => Flyology_Wire.Identities.Schema_Revision'First,
      Profile     => Flyology_Wire.Identities.Profile_ID'First);

   type Header is record
      Payload_Size           : Flyology_Wire.Byte_Count := 0;
      Message_Value          : Messages.Message_ID := Messages.No_Message_ID;
      Correlation_Value      : Messages.Message_ID := Messages.No_Message_ID;
      Source_Slot_Value      : Endpoints.Endpoint_Slot := Endpoints.No_Endpoint_Slot;
      Source_Generation_Value : Endpoints.Endpoint_Generation := Endpoints.No_Endpoint_Generation;
      Destination_Slot_Value : Endpoints.Endpoint_Slot := Endpoints.No_Endpoint_Slot;
      Destination_Generation_Value : Endpoints.Endpoint_Generation := Endpoints.No_Endpoint_Generation;
      Writer_Value           : Flyology_Wire.Identities.Schema_Identity := Invalid_Writer;
   end record;

   No_Header : constant Header := (others => <>);
end Flyology.Remoting.Protocol.V1.Headers;
