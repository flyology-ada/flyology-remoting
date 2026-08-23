--  Common bounded-node outcomes. Concrete node implementations route opaque
--  payload ownership without exposing their transport selection.

package Flyology.Remoting.Nodes
  with Preelaborate
is

   type Claim_Result is (Endpoint_Claimed, Directory_Full, Generation_Exhausted);

   type Try_Send_Result is
     (Message_Accepted,
      Backpressure,
      Foreign_Node,
      Stale_Incarnation,
      Stale_Endpoint,
      Endpoint_Closing,
      Local_Resource_Exhausted);

   type Try_Receive_Result is
     (Message_Received,
      No_Message,
      Foreign_Node,
      Stale_Incarnation,
      Stale_Endpoint,
      Endpoint_Closing,
      Local_Resource_Exhausted);

   type Close_Result is
     (Endpoint_Closed, Close_Already_In_Progress, Foreign_Node, Stale_Incarnation, Stale_Endpoint);

   type Node_Snapshot is record
      Active    : Natural;
      Closing   : Natural;
      Available : Natural;
      Exhausted : Natural;
   end record;

   Invalid_Owner : exception;

end Flyology.Remoting.Nodes;
