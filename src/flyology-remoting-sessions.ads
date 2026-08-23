with Flyology.Remoting.Endpoints;
with Flyology.Remoting.Identities;

--  Binds one valid live-session reference to the node role held by this
--  process. A binding carries routing and incarnation freshness data only; it
--  does not authenticate either node or prove reachability or liveness.

package Flyology.Remoting.Sessions
  with Preelaborate
is

   type Session_Role is (Initiator_Role, Acceptor_Role);

   --  A role-bound semantic view of one live session. The value contains no
   --  transport object, native address, or encoded envelope representation.
   type Binding is private;
   No_Binding : constant Binding;

   --  Report whether the binding contains a complete session reference.
   function Is_Valid (Value : Binding) return Boolean;

   Invalid_Session : exception;

   --  Bind a complete session reference. Invalid references raise
   --  Invalid_Session. The caller remains responsible for supplying a
   --  Session_ID that is not reused across live sessions and for supplying
   --  the local role established by the session owner or handshake.
   function Bind
     (Reference : Identities.Session_Reference; Role : Session_Role) return Binding;

   --  Return the exact values retained by the binding.
   function Reference (Value : Binding) return Identities.Session_Reference
   with Pre => Is_Valid (Value);
   function Role (Value : Binding) return Session_Role
   with Pre => Is_Valid (Value);
   function Local_Node (Value : Binding) return Identities.Node_Reference
   with Pre => Is_Valid (Value);
   function Peer_Node (Value : Binding) return Identities.Node_Reference
   with Pre => Is_Valid (Value);

   --  Validate a directional endpoint pair without consulting a transport.
   --  Outbound requires an exact local-incarnation source and exact peer-
   --  incarnation destination; inbound requires the reverse. Both endpoints
   --  must also contain valid nonzero slots and generations.
   function Is_Valid_Outbound_Route
     (Value       : Binding;
      Source      : Endpoints.Endpoint_Reference;
      Destination : Endpoints.Endpoint_Reference) return Boolean;

   function Is_Valid_Inbound_Route
     (Value       : Binding;
      Source      : Endpoints.Endpoint_Reference;
      Destination : Endpoints.Endpoint_Reference) return Boolean;

private
   type Binding is record
      Local_Role   : Session_Role := Initiator_Role;
      Session_Value : Identities.Session_Reference := Identities.No_Session;
   end record;

   No_Binding : constant Binding := (others => <>);

end Flyology.Remoting.Sessions;
