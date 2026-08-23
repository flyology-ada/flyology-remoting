package body Flyology.Remoting.Sessions is
   use type Identities.Node_Reference;

   function Is_Valid (Value : Binding) return Boolean is
     (Identities.Is_Valid (Value.Session_Value));

   function Bind
     (Reference : Identities.Session_Reference; Role : Session_Role) return Binding
   is
   begin
      if not Identities.Is_Valid (Reference) then
         raise Invalid_Session;
      end if;

      return (Local_Role => Role, Session_Value => Reference);
   end Bind;

   function Reference (Value : Binding) return Identities.Session_Reference is
     (Value.Session_Value);

   function Role (Value : Binding) return Session_Role is
     (Value.Local_Role);

   function Local_Node (Value : Binding) return Identities.Node_Reference is
     (if Value.Local_Role = Initiator_Role
      then Identities.Initiator (Value.Session_Value)
      else Identities.Acceptor (Value.Session_Value));

   function Peer_Node (Value : Binding) return Identities.Node_Reference is
     (if Value.Local_Role = Initiator_Role
      then Identities.Acceptor (Value.Session_Value)
      else Identities.Initiator (Value.Session_Value));

   function Is_Valid_Outbound_Route
     (Value       : Binding;
      Source      : Endpoints.Endpoint_Reference;
      Destination : Endpoints.Endpoint_Reference) return Boolean is
     (Is_Valid (Value)
      and then Endpoints.Is_Valid (Source)
      and then Endpoints.Is_Valid (Destination)
      and then Endpoints.Destination_Node (Source) = Local_Node (Value)
      and then Endpoints.Destination_Node (Destination) = Peer_Node (Value));

   function Is_Valid_Inbound_Route
     (Value       : Binding;
      Source      : Endpoints.Endpoint_Reference;
      Destination : Endpoints.Endpoint_Reference) return Boolean is
     (Is_Valid (Value)
      and then Endpoints.Is_Valid (Source)
      and then Endpoints.Is_Valid (Destination)
      and then Endpoints.Destination_Node (Source) = Peer_Node (Value)
      and then Endpoints.Destination_Node (Destination) = Local_Node (Value));

end Flyology.Remoting.Sessions;
