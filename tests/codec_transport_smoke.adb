with Ada.Streams;
with Flyology.Buffers;
with Flyology.Remoting.Codecs.In_Process;
with Flyology.Remoting.Endpoints;
with Flyology.Remoting.Identities;
with Flyology.Remoting.Nodes;
with Flyology.Remoting.Nodes.In_Process;
with Flyology.Remoting.Transports.In_Process;
with Flyology_Wire.Codecs;
with Remoting_Test_Codec;
with System;

procedure Codec_Transport_Smoke is
   package Buffers renames Flyology.Buffers;
   package Endpoints renames Flyology.Remoting.Endpoints;
   package Identities renames Flyology.Remoting.Identities;
   package Nodes renames Flyology.Remoting.Nodes;
   package Wire_Codecs renames Flyology_Wire.Codecs;

   use type Ada.Streams.Stream_Element_Array;
   use type Buffers.Pool_Snapshot;
   use type Nodes.Claim_Result;
   use type Nodes.Try_Receive_Result;
   use type Nodes.Try_Send_Result;
   use type Remoting_Test_Codec.Value;
   use type System.Address;
   use type Wire_Codecs.Decode_Status;
   use type Wire_Codecs.Encode_Status;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Assert;

   Storage : aliased Buffers.Pool (Block_Size => 16, Capacity => 3);

   package Local is new
     Flyology.Remoting.Nodes.In_Process
       (Storage                                      => Storage'Access,
        Endpoint_Capacity                            => 1,
        Mailbox_Capacity                             => 1,
        Maximum_Concurrent_Operations_Per_Endpoint => 2);

   package Typed is new
     Flyology.Remoting.Codecs.In_Process
       (Transport => Local.Payload_Transport,
        Codec     => Remoting_Test_Codec.Contract);

   Small_Storage : aliased Buffers.Pool (Block_Size => 3, Capacity => 1);

   package Small_Transport is new
     Flyology.Remoting.Transports.In_Process (Queue_Capacity => 1);

   package Small_Typed is new
     Flyology.Remoting.Codecs.In_Process
       (Transport => Small_Transport,
        Codec     => Remoting_Test_Codec.Contract);

   Owner : constant Identities.Node_Reference :=
     Identities.Make_Node_Reference
       (Identities.Node_ID_From_Words (16#1001#, 16#1002#),
        Identities.Incarnation_ID_From_Words (16#2001#, 16#2002#));
   Source : constant Remoting_Test_Codec.Value := (Number => 300, Valid => True);

   Server         : aliased Local.Node := Local.Create (Owner);
   Endpoint_Owner : constant Local.Endpoint_Handle (Server'Access) := Local.Claim (Server'Access);
   Endpoint       : constant Endpoints.Endpoint_Reference := Local.Reference (Endpoint_Owner);
   Reserved       : Local.Writable_Payload;
   Outbound       : Local.Writable_Payload;
   Inbound        : Local.Received_Payload;
   Small          : Small_Transport.Writable_Payload (Small_Storage'Access);
   Encoded        : Wire_Codecs.Encode_Status;
   Decoded        : Wire_Codecs.Decode_Status;
   Send           : Nodes.Try_Send_Result;
   Receive_Result : Nodes.Try_Receive_Result;
   Result         : Remoting_Test_Codec.Value;
   Wrong_Writer   : Wire_Codecs.Schema_Identity := Remoting_Test_Codec.Contract.Descriptor.Schema;
   Before         : System.Address := System.Null_Address;
   After          : System.Address := System.Null_Address;

   procedure Remember_Before (Data : Ada.Streams.Stream_Element_Array) is
   begin
      Before := Data'Address;
      Assert (Data = [1, 2, 16#AC#, 2], "Profile 1 codec produced unexpected bytes");
   end Remember_Before;

   procedure Remember_After (Data : Ada.Streams.Stream_Element_Array) is
   begin
      After := Data'Address;
   end Remember_After;

   procedure Check_Small (Data : Ada.Streams.Stream_Element_Array) is
   begin
      Assert (Data = [16#AA#, 16#BB#], "short-destination failure changed readable bytes");
   end Check_Small;

   procedure Check_Invalid (Data : Ada.Streams.Stream_Element_Array) is
   begin
      Assert (Data = [1 => 9], "invalid-value failure changed readable bytes");
   end Check_Invalid;
begin
   Assert (Local.Status (Endpoint_Owner) = Nodes.Endpoint_Claimed, "typed endpoint claim failed");
   Assert (Wire_Codecs.Is_Valid (Remoting_Test_Codec.Contract.Descriptor), "test descriptor is invalid");

   Small_Transport.Acquire (Small);
   Small_Transport.Copy_From (Small, [16#AA#, 16#BB#]);
   Small_Typed.Encode (Source, Small, Encoded);
   Assert
     (Encoded = Wire_Codecs.Destination_Too_Small and then Small_Transport.Length (Small) = 2,
      "short payload did not preserve its prior readable length");
   Small_Transport.With_Readable_Data (Small, Check_Small'Access);
   Small_Transport.Release (Small);

   --  Hold the first pool slot so codec callbacks receive a non-unit lower
   --  bound from the next slot.
   Local.Payload_Transport.Acquire (Reserved);
   Local.Payload_Transport.Acquire (Outbound);
   Local.Payload_Transport.Copy_From (Outbound, [9]);
   Typed.Encode ((Number => 0, Valid => False), Outbound, Encoded);
   Assert
     (Encoded = Wire_Codecs.Invalid_Value and then Local.Payload_Transport.Length (Outbound) = 1,
      "invalid value encode committed a new payload length");
   Local.Payload_Transport.With_Readable_Data (Outbound, Check_Invalid'Access);

   Typed.Encode (Source, Outbound, Encoded);
   Assert
     (Encoded = Wire_Codecs.Encoded and then Local.Payload_Transport.Length (Outbound) = 4,
      "typed payload did not encode directly into its lease");
   Local.Payload_Transport.With_Readable_Data (Outbound, Remember_Before'Access);
   Local.Try_Send (Server, Endpoint, Outbound, Send);
   Assert (Send = Nodes.Message_Accepted, "typed node send was not accepted");
   Local.Try_Receive (Server, Endpoint, Inbound, Receive_Result);
   Assert (Receive_Result = Nodes.Message_Received, "typed node receive failed");
   Local.Payload_Transport.With_Readable_Data (Inbound, Remember_After'Access);
   Assert (Before = After, "typed in-process delivery copied or replaced payload storage");

   Wrong_Writer.Fingerprint := [0 => 16#C2#, others => 0];
   Typed.Decode (Wrong_Writer, Inbound, Result, Decoded);
   Assert
     (Decoded = Wire_Codecs.Incompatible and then Result = (Number => 0, Valid => False),
      "incompatible writer schema was accepted or published a partial value");

   Typed.Decode (Remoting_Test_Codec.Contract.Descriptor.Schema, Inbound, Result, Decoded);
   Assert
     (Decoded = Wire_Codecs.Decoded and then Result = Source,
      "typed payload did not round trip through the node");
   Local.Payload_Transport.Release (Inbound);

   Local.Payload_Transport.Acquire (Outbound);
   Local.Payload_Transport.Copy_From (Outbound, [1, 1, 16#80#]);
   Local.Try_Send (Server, Endpoint, Outbound, Send);
   Assert (Send = Nodes.Message_Accepted, "malformed payload setup send failed");
   Local.Try_Receive (Server, Endpoint, Inbound, Receive_Result);
   Assert (Receive_Result = Nodes.Message_Received, "malformed payload setup receive failed");
   Typed.Decode (Remoting_Test_Codec.Contract.Descriptor.Schema, Inbound, Result, Decoded);
   Assert
     (Decoded = Wire_Codecs.Malformed and then Result = (Number => 0, Valid => False),
      "malformed payload was accepted or published a partial value");
   Local.Payload_Transport.Release (Inbound);

   Local.Payload_Transport.Acquire (Outbound);
   Local.Payload_Transport.Copy_From (Outbound, [1, 2, 16#81#, 0]);
   Local.Try_Send (Server, Endpoint, Outbound, Send);
   Assert (Send = Nodes.Message_Accepted, "noncanonical payload setup send failed");
   Local.Try_Receive (Server, Endpoint, Inbound, Receive_Result);
   Assert (Receive_Result = Nodes.Message_Received, "noncanonical payload setup receive failed");
   Typed.Decode (Remoting_Test_Codec.Contract.Descriptor.Schema, Inbound, Result, Decoded);
   Assert
     (Decoded = Wire_Codecs.Noncanonical and then Result = (Number => 0, Valid => False),
      "noncanonical payload was accepted or published a partial value");
   Local.Payload_Transport.Release (Inbound);
   Local.Payload_Transport.Release (Reserved);

   Assert
     (Buffers.Current (Storage) = (Available => 3, Outstanding => 0),
      "typed codec path leaked a payload slot");
end Codec_Transport_Smoke;
