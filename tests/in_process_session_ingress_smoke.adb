with Flyology.Buffers;
with Flyology.Remoting.Codecs.Payload_Leases;
with Flyology.Remoting.Endpoints;
with Flyology.Remoting.Identities;
with Flyology.Remoting.Messages;
with Flyology.Remoting.Sessions;
with Flyology.Remoting.Sessions.In_Process;
with Flyology_Wire.Codecs;
with Flyology_Wire.Identities;
with Remoting_Test_Codec;

procedure In_Process_Session_Ingress_Smoke is
   package Buffers renames Flyology.Buffers;
   package Endpoints renames Flyology.Remoting.Endpoints;
   package Identities renames Flyology.Remoting.Identities;
   package Messages renames Flyology.Remoting.Messages;
   package Sessions renames Flyology.Remoting.Sessions;
   package Wire_Codecs renames Flyology_Wire.Codecs;
   package Wire_Identities renames Flyology_Wire.Identities;

   package Ingress is new
     Flyology.Remoting.Sessions.In_Process
       (Queue_Capacity => 2, Maximum_Concurrent_Builders => 1);

   package Typed is new
     Flyology.Remoting.Codecs.Payload_Leases
       (Writable_Payload   => Ingress.Writable_Payload,
        Received_Payload   => Ingress.Accepted_Message,
        Has_Writable       => Ingress.Has_Payload,
        Has_Received       => Ingress.Has_Message,
        Capacity           => Ingress.Payload_Capacity,
        With_Writable_Data => Ingress.With_Writable_Data,
        With_Readable_Data => Ingress.With_Readable_Data,
        Codec              => Remoting_Test_Codec.Contract);

   use type Buffers.Pool_Snapshot;
   use type Endpoints.Endpoint_Reference;
   use type Identities.Identity_Word;
   use type Ingress.Try_Send_Result;
   use type Ingress.Try_Take_Result;
   use type Messages.Message_ID;
   use type Remoting_Test_Codec.Value;
   use type Sessions.Binding;
   use type Wire_Codecs.Decode_Status;
   use type Wire_Codecs.Encode_Status;
   use type Wire_Identities.Schema_Identity;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Assert;

   function Make_Node (Base : Identities.Identity_Word) return Identities.Node_Reference is
     (Identities.Make_Node_Reference
        (Identities.Node_ID_From_Words (Base, Base + 1),
         Identities.Incarnation_ID_From_Words (Base + 2, Base + 3)));

   function Make_Endpoint
     (Node : Identities.Node_Reference;
      Slot : Endpoints.Endpoint_Word) return Endpoints.Endpoint_Reference
   is
     (Endpoints.Make_Endpoint_Reference
        (Node, Endpoints.Slot_From_Word (Slot), Endpoints.Generation_From_Word (Slot + 10)));

   function Make_Message (Value : Flyology_Wire.Octet) return Messages.Message_ID is
     (Messages.Message_ID_From_Bytes ([others => Value]));

   Initiator_Node : constant Identities.Node_Reference := Make_Node (10);
   Acceptor_Node  : constant Identities.Node_Reference := Make_Node (20);
   Session_Value  : constant Identities.Session_Reference :=
     Identities.Make_Session_Reference
       (Initiator_Node, Acceptor_Node, Identities.Session_ID_From_Words (30, 31));
   Reconnected_Value : constant Identities.Session_Reference :=
     Identities.Make_Session_Reference
       (Initiator_Node, Acceptor_Node, Identities.Session_ID_From_Words (30, 32));
   Initiator_Binding : constant Sessions.Binding :=
     Sessions.Bind (Session_Value, Sessions.Initiator_Role);
   Acceptor_Binding : constant Sessions.Binding :=
     Sessions.Bind (Session_Value, Sessions.Acceptor_Role);
   Reconnected_Binding : constant Sessions.Binding :=
     Sessions.Bind (Reconnected_Value, Sessions.Initiator_Role);
   Initiator_Endpoint : constant Endpoints.Endpoint_Reference := Make_Endpoint (Initiator_Node, 1);
   Acceptor_Endpoint  : constant Endpoints.Endpoint_Reference := Make_Endpoint (Acceptor_Node, 2);
   Foreign_Endpoint   : constant Endpoints.Endpoint_Reference := Make_Endpoint (Make_Node (40), 3);
   First_Message      : constant Messages.Message_ID := Make_Message (1);
   Forwarded_Message  : constant Messages.Message_ID := Make_Message (2);
   Source_Value       : constant Remoting_Test_Codec.Value := (Number => 300, Valid => True);

   Payload_Storage    : aliased Buffers.Pool (Block_Size => 16, Capacity => 3);
   Initiator_Headers  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
   Acceptor_Headers   : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);
   Reconnect_Headers  : aliased Buffers.Pool (Block_Size => 144, Capacity => 4);

   Initiator_Ingress : Ingress.Session :=
     Ingress.Create (Initiator_Binding, Payload_Storage'Access, Initiator_Headers'Access);
   Acceptor_Ingress : Ingress.Session :=
     Ingress.Create (Acceptor_Binding, Payload_Storage'Access, Acceptor_Headers'Access);
   Reconnected_Ingress : Ingress.Session :=
     Ingress.Create (Reconnected_Binding, Payload_Storage'Access, Reconnect_Headers'Access);

   Outbound       : Ingress.Writable_Payload (Payload_Storage'Access);
   Invalid        : Ingress.Writable_Payload (Payload_Storage'Access);
   Accepted       : Ingress.Accepted_Message (Payload_Storage'Access, Initiator_Headers'Access);
   Forwarded      : Ingress.Accepted_Message (Payload_Storage'Access, Acceptor_Headers'Access);
   Reconnect_Message : Ingress.Accepted_Message (Payload_Storage'Access, Reconnect_Headers'Access);
   Encoded        : Wire_Codecs.Encode_Status;
   Decoded        : Wire_Codecs.Decode_Status;
   Send_Result    : Ingress.Try_Send_Result;
   Take_Result    : Ingress.Try_Take_Result;
   Decoded_Value  : Remoting_Test_Codec.Value;
   Wrong_Writer   : Wire_Identities.Schema_Identity := Remoting_Test_Codec.Contract.Descriptor.Schema;
begin
   Ingress.Acquire (Outbound);
   Typed.Encode (Source_Value, Outbound, Encoded);
   Assert (Encoded = Wire_Codecs.Encoded, "typed session payload did not encode");
   Ingress.Try_Send
     (Initiator_Ingress,
      Initiator_Endpoint,
      Acceptor_Endpoint,
      First_Message,
      Messages.No_Message_ID,
      Remoting_Test_Codec.Contract.Descriptor.Schema,
      Outbound,
      Send_Result);
   Assert
     (Send_Result = Ingress.Message_Accepted and then not Ingress.Has_Payload (Outbound),
      "exact-binding session ingress did not accept the typed payload");

   Ingress.Try_Take_Accepted (Reconnected_Ingress, Reconnect_Message, Take_Result);
   Assert
     (Take_Result = Ingress.No_Accepted_Message,
      "reconnected binding observed an earlier session entry");
   Ingress.Try_Take_Accepted (Initiator_Ingress, Accepted, Take_Result);
   Assert (Take_Result = Ingress.Accepted_Message_Taken, "accepted descriptor was unavailable");
   Assert (Ingress.Session_Binding (Accepted) = Initiator_Binding, "accepted binding changed");
   Assert (Ingress.Source (Accepted) = Initiator_Endpoint, "source endpoint reconstruction changed");
   Assert
     (Ingress.Destination (Accepted) = Acceptor_Endpoint,
      "destination endpoint reconstruction changed");
   Assert (Ingress.Message (Accepted) = First_Message, "message identity changed");
   Typed.Decode
     (Ingress.Writer (Accepted), Accepted, Decoded_Value, Decoded);
   Assert
     (Decoded = Wire_Codecs.Decoded and then Decoded_Value = Source_Value,
      "typed payload did not decode under the accepted writer identity");

   Ingress.Try_Forward
     (Acceptor_Ingress,
      Acceptor_Endpoint,
      Initiator_Endpoint,
      Forwarded_Message,
      First_Message,
      Remoting_Test_Codec.Contract.Descriptor.Schema,
      Accepted,
      Send_Result);
   Assert
     (Send_Result = Ingress.Message_Accepted and then Ingress.Is_Vacant (Accepted),
      "cross-pool session forwarding did not transfer the accepted payload");
   Ingress.Try_Take_Accepted (Acceptor_Ingress, Forwarded, Take_Result);
   Assert (Take_Result = Ingress.Accepted_Message_Taken, "forwarded descriptor was unavailable");
   Assert (Ingress.Session_Binding (Forwarded) = Acceptor_Binding, "forwarded binding changed");
   Assert (Ingress.Source (Forwarded) = Acceptor_Endpoint, "forwarded source changed");
   Assert (Ingress.Destination (Forwarded) = Initiator_Endpoint, "forwarded destination changed");
   Assert
     (Ingress.Correlation (Forwarded) = First_Message,
      "forwarded correlation changed");
   Typed.Decode
     (Ingress.Writer (Forwarded), Forwarded, Decoded_Value, Decoded);
   Assert
     (Decoded = Wire_Codecs.Decoded and then Decoded_Value = Source_Value,
      "forwarding changed the opaque encoded payload");
   Ingress.Release (Forwarded);

   Wrong_Writer.Fingerprint := [0 => 16#C2#, others => 0];
   Ingress.Acquire (Outbound);
   Typed.Encode (Source_Value, Outbound, Encoded);
   Assert (Encoded = Wire_Codecs.Encoded, "writer pass-through payload did not encode");
   Ingress.Try_Send
     (Initiator_Ingress,
      Initiator_Endpoint,
      Acceptor_Endpoint,
      Make_Message (3),
      Messages.No_Message_ID,
      Wrong_Writer,
      Outbound,
      Send_Result);
   Assert (Send_Result = Ingress.Message_Accepted, "distinct valid writer was rejected");
   Ingress.Try_Take_Accepted (Initiator_Ingress, Accepted, Take_Result);
   Assert (Take_Result = Ingress.Accepted_Message_Taken, "writer pass-through message was unavailable");
   Assert (Ingress.Writer (Accepted) = Wrong_Writer, "session substituted the local codec writer");
   Typed.Decode (Ingress.Writer (Accepted), Accepted, Decoded_Value, Decoded);
   Assert
     (Decoded = Wire_Codecs.Incompatible,
      "session writer pass-through did not drive directional codec compatibility");
   Ingress.Release (Accepted);

   Ingress.Acquire (Invalid);
   Ingress.Copy_From (Invalid, [9]);
   Ingress.Close (Initiator_Ingress);
   Ingress.Try_Send
     (Initiator_Ingress,
      Foreign_Endpoint,
      Acceptor_Endpoint,
      Messages.No_Message_ID,
      Messages.No_Message_ID,
      Remoting_Test_Codec.Contract.Descriptor.Schema,
      Invalid,
      Send_Result);
   Assert
     (Send_Result = Ingress.Invalid_Message_Context and then Ingress.Has_Payload (Invalid),
      "message validation did not precede route and closure classification");
   Ingress.Try_Send
     (Initiator_Ingress,
      Foreign_Endpoint,
      Acceptor_Endpoint,
      Make_Message (3),
      Messages.No_Message_ID,
      Remoting_Test_Codec.Contract.Descriptor.Schema,
      Invalid,
      Send_Result);
   Assert
     (Send_Result = Ingress.Invalid_Outbound_Route and then Ingress.Has_Payload (Invalid),
      "invalid outbound route consumed payload ownership");
   Ingress.Try_Send
     (Initiator_Ingress,
      Initiator_Endpoint,
      Acceptor_Endpoint,
      Make_Message (3),
      Messages.No_Message_ID,
      Remoting_Test_Codec.Contract.Descriptor.Schema,
      Invalid,
      Send_Result);
   Assert
     (Send_Result = Ingress.Session_Closed and then Ingress.Has_Payload (Invalid),
      "closed exact-binding session consumed payload ownership");
   Ingress.Release (Invalid);
   Ingress.Close (Acceptor_Ingress);
   Ingress.Close (Reconnected_Ingress);

   Assert
     (Buffers.Current (Payload_Storage) = (Available => 3, Outstanding => 0),
      "first typed session use leaked payload storage");
   Assert
     (Buffers.Current (Initiator_Headers) = (Available => 4, Outstanding => 0),
      "initiator session leaked header storage");
   Assert
     (Buffers.Current (Acceptor_Headers) = (Available => 4, Outstanding => 0),
      "acceptor session leaked header storage");
   Assert
     (Buffers.Current (Reconnect_Headers) = (Available => 4, Outstanding => 0),
      "reconnected session leaked header storage");
end In_Process_Session_Ingress_Smoke;
