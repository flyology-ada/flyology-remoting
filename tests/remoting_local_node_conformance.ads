with Ada.Streams;
with Flyology.Remoting.Endpoints;
with Flyology.Remoting.Identities;
with Flyology.Remoting.Nodes;

--  Reusable test contract for one immediate bounded local endpoint router.
--  It deliberately excludes session handshake, deadlines, cancellation,
--  disconnect, authorization, and remote delivery or receipt semantics.

generic
   Endpoint_Capacity : Positive;
   Mailbox_Capacity : Positive;

   type Local_Node (<>) is limited private;
   type Endpoint_Handle (<>) is limited private;
   type Writable_Payload is limited private;
   type Received_Payload is limited private;

   with function Create_Node (Owner : Flyology.Remoting.Identities.Node_Reference) return Local_Node;
   with function Node_Owner (Item : Local_Node) return Flyology.Remoting.Identities.Node_Reference;
   with function Claim (Item : not null access Local_Node) return Endpoint_Handle;
   with function Claim_Status (Item : Endpoint_Handle) return Flyology.Remoting.Nodes.Claim_Result;
   with function Has_Endpoint (Item : Endpoint_Handle) return Boolean;
   with function Reference (Item : Endpoint_Handle) return Flyology.Remoting.Endpoints.Endpoint_Reference;

   with function Create_Writable return Writable_Payload;
   with function Create_Received return Received_Payload;
   with procedure Acquire (Item : in out Writable_Payload);
   with procedure Release_Received (Item : in out Received_Payload);
   with function Has_Writable (Item : Writable_Payload) return Boolean;
   with function Has_Received (Item : Received_Payload) return Boolean;

   with procedure Copy_From
     (Item : in out Writable_Payload; Data : Ada.Streams.Stream_Element_Array);

   with procedure Read_Writable
     (Item : Writable_Payload;
      Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array));

   with procedure Read_Received
     (Item : Received_Payload;
      Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array));

   with procedure Try_Send_Writable
     (Item        : in out Local_Node;
      Destination : Flyology.Remoting.Endpoints.Endpoint_Reference;
      Value       : in out Writable_Payload;
      Result      : out Flyology.Remoting.Nodes.Try_Send_Result);

   with procedure Try_Send_Received
     (Item        : in out Local_Node;
      Destination : Flyology.Remoting.Endpoints.Endpoint_Reference;
      Value       : in out Received_Payload;
      Result      : out Flyology.Remoting.Nodes.Try_Send_Result);

   with procedure Try_Receive
     (Item     : in out Local_Node;
      Endpoint : Flyology.Remoting.Endpoints.Endpoint_Reference;
      Target   : in out Received_Payload;
      Result   : out Flyology.Remoting.Nodes.Try_Receive_Result);

   with procedure Close
     (Item : in out Endpoint_Handle; Result : out Flyology.Remoting.Nodes.Close_Result);

   with function Is_Current
     (Item : Local_Node; Endpoint : Flyology.Remoting.Endpoints.Endpoint_Reference) return Boolean;

   with function Current (Item : Local_Node) return Flyology.Remoting.Nodes.Node_Snapshot;
   with function Resources_Balanced return Boolean;

package Remoting_Local_Node_Conformance is

   --  Qualify a one-endpoint, two-message-mailbox router. The shared payload
   --  resource must provide at least three simultaneously owned payloads.
   procedure Run;

end Remoting_Local_Node_Conformance;
