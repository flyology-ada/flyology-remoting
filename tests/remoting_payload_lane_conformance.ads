with Ada.Streams;
with Flyology.Remoting.Transports;

--  Reusable test contract for the immediate bounded opaque-payload lane.
--  This is deliberately narrower than session conformance: it has no
--  handshake, deadline, cancellation, disconnect, or remote receipt surface.

generic
   type Lane is limited private;
   type Writable_Payload is limited private;
   type Received_Payload is limited private;
   Lane_Capacity : Positive;

   with function Create_Lane return Lane;
   with function Create_Writable return Writable_Payload;
   with function Create_Received return Received_Payload;
   with procedure Acquire (Item : in out Writable_Payload);
   with procedure Release_Writable (Item : in out Writable_Payload);
   with procedure Release_Received (Item : in out Received_Payload);
   with function Has_Writable (Item : Writable_Payload) return Boolean;
   with function Has_Received (Item : Received_Payload) return Boolean;
   with function Length_Writable (Item : Writable_Payload) return Natural;
   with function Length_Received (Item : Received_Payload) return Natural;

   with procedure Copy_From
     (Item : in out Writable_Payload; Data : Ada.Streams.Stream_Element_Array);

   with procedure Read_Writable
     (Item    : Writable_Payload;
      Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array));

   with procedure Read_Received
     (Item    : Received_Payload;
      Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array));

   with procedure Try_Send_Writable
     (Item   : in out Lane;
      Value  : in out Writable_Payload;
      Result : out Flyology.Remoting.Transports.Try_Send_Result);

   with procedure Try_Send_Received
     (Item   : in out Lane;
      Value  : in out Received_Payload;
      Result : out Flyology.Remoting.Transports.Try_Send_Result);

   with procedure Try_Receive
     (Item   : in out Lane;
      Target : in out Received_Payload;
      Result : out Flyology.Remoting.Transports.Try_Receive_Result);

   with procedure Close (Item : in out Lane);
   with function Current (Item : Lane) return Flyology.Remoting.Transports.Lane_Snapshot;
   with function Resources_Balanced return Boolean;

package Remoting_Payload_Lane_Conformance is

   --  Qualify a two-slot lane instance. The shared payload resource must
   --  provide at least three simultaneously owned payloads.
   procedure Run;

end Remoting_Payload_Lane_Conformance;
