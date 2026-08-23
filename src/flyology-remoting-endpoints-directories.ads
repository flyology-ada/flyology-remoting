with Flyology.Remoting.Identities;

--  Supplies a bounded, task-safe allocator for local endpoint references.
--  Reusing a slot advances its generation; generation exhaustion permanently
--  removes that slot rather than wrapping to a stale value.

generic
   Capacity : Positive;
package Flyology.Remoting.Endpoints.Directories is

   type Directory (<>) is limited private;

   --  Result of a bounded nonblocking endpoint claim.
   type Claim_Result is (Endpoint_Claimed, Directory_Full, Generation_Exhausted);
   --  Classification of an endpoint release attempt.
   type Release_Result is (Released, Foreign_Node, Stale_Incarnation, Stale_Endpoint);

   --  Coherent directory capacity and lifecycle counts.
   type Directory_Snapshot is record
      Active    : Natural;
      Available : Natural;
      Exhausted : Natural;
   end record;

   Invalid_Owner : exception;

   --  Create a directory for one complete node incarnation.
   --  @param Owner Node incarnation that owns every claimed endpoint
   --  @return Fresh empty directory
   --  @exception Invalid_Owner Owner contains an invalid-zero identity
   function Create (Owner : Identities.Node_Reference) return Directory;

   --  Return the node incarnation that owns this directory.
   function Owner (Item : Directory) return Identities.Node_Reference;

   --  Claim one free slot without waiting. Success returns its current generation.
   procedure Try_Claim
     (Item : in out Directory; Reference : out Endpoint_Reference; Result : out Claim_Result)
   with Post => (Result = Endpoint_Claimed) = Is_Valid (Reference);

   --  Release only an exact current reference and classify stale or foreign values.
   procedure Release
     (Item : in out Directory; Reference : Endpoint_Reference; Result : out Release_Result);

   --  Report whether Reference names an active slot in this exact node incarnation.
   function Is_Current (Item : Directory; Reference : Endpoint_Reference) return Boolean;

   --  Return a protected snapshot of bounded directory state.
   function Current (Item : Directory) return Directory_Snapshot;

private
   subtype Slot_Index is Positive range 1 .. Capacity;
   type Active_Array is array (Slot_Index) of Boolean;
   type Generation_Array is array (Slot_Index) of Endpoint_Generation;

   protected type Directory_State is
      procedure Try_Claim
        (Claimed_Slot : out Endpoint_Slot;
         Claimed_Generation : out Endpoint_Generation;
         Result : out Claim_Result);
      procedure Release
        (Released_Slot : Endpoint_Slot;
         Released_Generation : Endpoint_Generation;
         Was_Current : out Boolean);
      function Is_Current
        (Current_Slot : Endpoint_Slot; Current_Generation : Endpoint_Generation) return Boolean;
      function Current return Directory_Snapshot;
   private
      Active      : Active_Array := (others => False);
      Generations : Generation_Array := (others => No_Endpoint_Generation);
      Active_Count : Natural := 0;
   end Directory_State;

   type Directory is limited record
      Owner_Node : Identities.Node_Reference;
      State      : Directory_State;
   end record;

end Flyology.Remoting.Endpoints.Directories;
