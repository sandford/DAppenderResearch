module core.appender3;

import core.memory;
import std.array;
import std.traits;
import std.algorithm;
import std.range;
import std.exception;
import core.bitop;

/** Implements an output range which stores appended data. This is recommended
 *  over $(D a ~= data) when appending many elements because it is more memory
 *  and computationally efficient.
 *
 *  Example:
    ----
    auto buffer = Appender!(char[])(4);             // Reserve 4 elements
    foreach( str; ["Hello"d, "World"d] ) {
        buffer.clear;                               // Use appender as a
        foreach( dchar c; str )                     // dynamically sized buffer
            put( buffer, c    );
        assert( buffer.data == str );
    }

    int[] a = [ 1, 2 ];
    auto builder = appender(a);                     // Or for array building
    builder.put(3);
    builder.put([ 4, 5, 6 ]);
    assert(builder.data == [ 1, 2, 3, 4, 5, 6 ]);
    ----
 */
/* Changes: This is Issue 5813, requires Issue 5233 [my put patch]
    (*) Fixes a memory leak when putting an array
    (*) Fixes Issue 4287 - opOpAssign!("~=") for std.array.Appender
    (*) Fixes lack of toString method
    (*) Fixes lack of to/opCast conversion routines

    Chain based architecture
    allocations only flattened on call to data
    opSlice provides a zero-overhead walker of the data structure.
    Faster

TODO:

Add [] slicing (range of ranges) or (range of T? struct{Node*,Index}
Add opIndex ?
Add opSlice [5..6]?

*/

// in progress
struct Appender3_wip(A : T[], T) {
    private {
        enum  PageSize = 4096;          // Memory page size
        enum  InitSize = 128;           // Default initialization size 

        alias Unqual!T E;               // Internal element type

        struct Data {
            Data*   next;               // The next data segment
            E*      base;               // The base address of this segment
            E*      ptr;                // Pointer to the empty segment
            size_t  slack;              // The amount of remaining capacity

            // Returns: the number of elements in this segment
            size_t capacity() const pure nothrow {
                return length + slack;
            }
            // Returns: the number of used elements in this segment
            size_t length() const pure nothrow {
                return ptr - base;
            }

            // Initialize a segment using an existing array
            void opAssign(E[] _arr) pure nothrow {
                auto cap = _arr.capacity;
                next     = null;
                base     = _arr.ptr;
                ptr      = _arr.ptr + _arr.length;
                slack    = cap - _arr.length;
                if(slack > 0 ) {
                    _arr.length = cap;
                }
            }

            // Create a new segment using an existing array
            this(Unqual!T[] _arr) pure nothrow { this = _arr; }

            // Create a new segment with at least size bytes
            this(size_t size) nothrow {
                enum NO_SCAN = hasIndirections!T ? 0 : GC.BlkAttr.NO_SCAN;
                auto bi      = GC.qalloc(size, NO_SCAN);
                next         = null;
                base         = (cast(E*)bi.base);
                ptr          = (cast(E*)bi.base);
                slack        = bi.size / T.sizeof;
            }
        }
        Data*  _head;           // The head data segment
        Data*  _tail;           // The last data segment

        // Returns: the total number of elements in the appender
        size_t _length() const pure nothrow {
            size_t len = 0;
            for(const(Data)* d = _head; d !is null; d = d.next)
                len    += d.length;
            return len;
        }

        // Flatten all the data segments into a single array
        E[] flatten() const pure nothrow {
            if(_head is _tail)
                return cast(E[])(_head ? _head.base[0.._head.length] : null);

            size_t N   = _length;
            size_t i   = 0;
            auto   arr = new E[N];
            size_t len;
            for(const(Data)* d = _head; N > 0; d = d.next, i += len) { ////////////////////////////////////// memcpy etc optimizations?
                len = d.length;
                arr[i..i+len] = d.base[0..len];
                //len    = min(N, d.length);
                //memcpy(arr.ptr+i, d.arr.ptr, len * T.sizeof);
            }
            return arr;
        }

        // Returns: the next capacity size
        size_t nextCapacity() const pure nothrow { return PageSize;
            auto   cap = _tail.capacity * T.sizeof * 2;
            return cap < PageSize ? cap : PageSize;
        }
    }

    /// Returns: the appender's data as an array.
    T[] data() pure nothrow {
return null;
        auto arr = flatten;
        if(_head !is _tail) {
            *_head = arr;
             _tail = _head;
        }
        return cast(T[]) arr;
    }

    /// Appends to the output range
    void put(U)(U item) if ( isOutputRange!(Unqual!T[],U) ){ 
        // put(T)
//        static if ( isImplicitlyConvertible!(U, E) ){
//assert(false, "Work on this latter");
//            //if(!_head)
//            //    _head = _tail  = new Data( 16 * T.sizeof );
//            //else if( _tail.arr.length == _tail.capacity  ) {   // Try extending
//            //    if( auto u = GC.extend(_tail.arr.ptr, T.sizeof, nextCapacity) )
//            //         _tail.capacity     = u / T.sizeof;
//            //    else _tail = _tail.next = new Data( nextCapacity );
//            //}
//            //auto          len  = _tail.arr.length;
//            //_tail.arr.ptr[len] = item;
//            //_tail.arr          = _tail.arr.ptr[0 .. len + 1];
//
//        // fast put(T[])
//        } else static if( is(typeof(_tail.arr[0..1] = item[0..1])) ){
            auto items  = cast(E[]) item[];
            if(!_tail || _tail.slack < items.length ) {
                if(_tail) {
                    // Fill up the remaining slack
                    _tail.ptr[0 .. _tail.slack] = items[0.._tail.slack];
                    _tail.ptr   += _tail.slack;
                    _tail.slack  = 0;

                    // Add another segment
                    items       = items[_tail.slack..$];
                    _tail.next  = new Data(max(items.length*T.sizeof,nextCapacity));
                    _tail       = _tail.next;
                } else {
                    _head=_tail= new Data(max(items.length*T.sizeof,InitSize));
                }
            }
            // Push the items
            _tail.ptr[0..items.length] = items;
            _tail.ptr   += items.length;
            _tail.slack -= items.length;
            //if(!_tail)
            //    _head   = _tail = new Data(  PageSize / T.sizeof );
            //auto arr    = _tail.arr.ptr[_tail.arr.length.._tail.capacity];
            
            //if(arr.length < len) {                             // Try extending
            //    auto size  = max(items.length*T.sizeof, nextCapacity);
            //    if( auto u = GC.extend(_tail.arr.ptr, T.sizeof, size) ) {
            //        _tail.capacity = u / T.sizeof;
            //        arr    = _tail.arr.ptr[_tail.arr.length.._tail.capacity];
            //    }
            //    if(arr.length < len) len = arr.length;
            //}
            //arr[0..len] = items[0..len];
            //items       = items[len..$];
            //_tail.arr   = _tail.arr.ptr[0 .. _tail.arr.length + len];
            //if( items.length > 0 ) {               // Add a segment and advance
            //    _tail.next = new Data(max(items.length*T.sizeof,nextCapacity));
            //    _tail      = _tail.next;
            //    _tail.arr.ptr[0..items.length] = items[];
            //    _tail.arr   = _tail.arr.ptr[0..items.length];
            //}

        // Everything else
//        } else {
//assert(false, "Work on this later");
// 
           // .put!(typeof(this),U,true,Unqual!T)(this,item);
        //}
    }
}






































struct Appender3_old(A : T[], T) {
    private {
        enum  PageSize = 4096;          // Memory page size
        alias Unqual!T E;               // Internal element type

        struct Data {
            Data*       next;           // The next data segment
            size_t      capacity;       // Capacity of this segment
            E[]         arr;            // This segment's array

            // Initialize a segment using an existing array
            void opAssign(E[] _arr) {
                next           = null;
                capacity       = _arr.capacity;
                arr            = _arr;
                if(_arr.length < capacity) {
                    arr.length = capacity;
                    arr.length = _arr.length;
                }
                assert(_arr.ptr is arr.ptr,"Unexpected reallocation occurred");
            }

            // Create a new segment using an existing array
            this(Unqual!T[] _arr) { this = _arr; }

            // Create a new segment with at least size bytes
            this(size_t size) {
                enum NO_SCAN = hasIndirections!T ? 0 : GC.BlkAttr.NO_SCAN;
                auto bi      = GC.qalloc(size, NO_SCAN);
                next         = null;
                capacity     = bi.size / T.sizeof;
                arr          = (cast(E*)bi.base)[0..0];
            }
        }
        Data*  _head;           // The head data segment
        Data*  _tail;           // The last data segment

        // Returns: the total number of elements in the appender
        size_t _length() {
            size_t len = 0;
            for(auto d = _head; d !is null; d = d.next)
                len   += d.arr.length;
            return len;
        }

        // Flatten all the data segments into a single array
        E[] flatten() {
            if(_head is _tail)
                return _head ? _head.arr : null;

            size_t N   = _length;
            size_t len = N;
            size_t i   = 0;
            auto arr   = new E[N];
            for(auto d = _head; N > 0; d = d.next, N -= len, i += len) {
                len    = min(N, d.arr.length);
                memcpy(arr.ptr+i, d.arr.ptr, len * T.sizeof);
            }
            return arr;
        }

        // Returns: the next capacity size
        size_t nextCapacity() nothrow pure {
            auto   cap = _tail.capacity * T.sizeof * 2;
            return cap < PageSize ? cap : PageSize;
        }
    }

    /// Returns: the appender's data as an array.
    T[] data() {
        auto arr = flatten;
        if(_head !is _tail) {
            *_head = arr;
             _tail = _head;
        }
        return cast(T[]) arr;
    }

    /// Appends to the output range
    void put(U)(U item) if ( isOutputRange!(Unqual!T[],U) ){ 
        // put(T)
        static if ( isImplicitlyConvertible!(U, E) ){
            if(!_head)
                _head = _tail  = new Data( 16 * T.sizeof );
            else if( _tail.arr.length == _tail.capacity  ) {   // Try extending
                if( auto u = GC.extend(_tail.arr.ptr, T.sizeof, nextCapacity) )
                     _tail.capacity     = u / T.sizeof;
                else _tail = _tail.next = new Data( nextCapacity );
            }
            auto          len  = _tail.arr.length;
            _tail.arr.ptr[len] = item;
            _tail.arr          = _tail.arr.ptr[0 .. len + 1];

        // fast put(T[])
        } else static if( is(typeof(_tail.arr[0..1] = item[0..1])) ){
            auto items  = cast(E[]) item[];
            if(!_tail)
                _head   = _tail = new Data(  items.length * T.sizeof );
            auto arr    = _tail.arr.ptr[_tail.arr.length.._tail.capacity];
            size_t len  = items.length;
            if(arr.length < len) {                             // Try extending
                auto size  = max(items.length*T.sizeof, nextCapacity);
                if( auto u = GC.extend(_tail.arr.ptr, T.sizeof, size) ) {
                    _tail.capacity = u / T.sizeof;
                    arr    = _tail.arr.ptr[_tail.arr.length.._tail.capacity];
                }
                if(arr.length < len) len = arr.length;
            }
            arr[0..len] = items[0..len];
            items       = items[len..$];
            _tail.arr   = _tail.arr.ptr[0 .. _tail.arr.length + len];
            if( items.length > 0 ) {               // Add a segment and advance
                _tail.next = new Data(max(items.length*T.sizeof,nextCapacity));
                _tail      = _tail.next;
                _tail.arr.ptr[0..items.length] = items[];
                _tail.arr   = _tail.arr.ptr[0..items.length];
            }

        // Everything else
        } else {
            .put!(typeof(this),U,true,Unqual!T)(this,item);
        }
    }
}











































//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
struct Appender3_full(A : T[], T) {
    private {
        enum  PageSize = 4096;          // Memory page size
        alias Unqual!T E;               // Internal element type

        struct Data {
            Data*       next;           // The next data segment
            size_t      capacity;       // Capacity of this segment
            E[]         arr;            // This segment's array

            // Initialize a segment using an existing array
            void opAssign(E[] _arr) {
                next           = null;
                capacity       = _arr.capacity;
                arr            = _arr;
                if(_arr.length < capacity) {
                    arr.length = capacity;
                    arr.length = _arr.length;
                }
                assert(_arr.ptr is arr.ptr,"Unexpected reallocation occurred");
            }

            // Create a new segment using an existing array
            this(Unqual!T[] _arr) { this = _arr; }

            // Create a new segment with at least size bytes
            this(size_t size) {
                enum NO_SCAN = hasIndirections!T ? 0 : GC.BlkAttr.NO_SCAN;
                auto bi      = GC.qalloc(size, NO_SCAN);
                next         = null;
                capacity     = bi.size / T.sizeof;
                arr          = (cast(E*)bi.base)[0..0];
            }
        }
        union {
            struct {
                Data*  _head;           // The head data segment
                Data*  _tail;           // The last data segment
            }
            T[] _ctfe_array;            // For the ctfe Appender
        };

        // Returns: the total number of elements in the appender
        size_t _length() {
            size_t len = 0;
            for(auto d = _head; d !is null; d = d.next)
                len   += d.arr.length;
            return len;
        }

        // Flatten all the data segments into a single array
        E[] flatten() {
            if(_head is _tail)
                return _head ? _head.arr : null;

            size_t N   = _length;
            size_t len = N;
            size_t i   = 0;
            auto arr   = new E[N];
            for(auto d = _head; N > 0; d = d.next, N -= len, i += len) {
                len    = min(N, d.arr.length);
                memcpy(arr.ptr+i, d.arr.ptr, len * T.sizeof);
            }
            return arr;
        }

        // Returns: the next capacity size
        size_t nextCapacity() nothrow pure {
            auto   cap = _tail.capacity * T.sizeof * 2;
            return cap < PageSize ? cap : PageSize;
        }
    }

    /** Construct an appender with a given array.  Note that this does not copy
     *  the data.  If the array has a larger capacity as determined by
     *  arr.capacity, it will be used by the appender.  After initializing an
     *  appender on an array, appending to the original array will reallocate.
     */
    this(T[] arr) {
        if(__ctfe) {
            _ctfe_array = arr;
        } else {
            if(arr is null) _head = _tail = new Data( 16 * T.sizeof );
            else            _head = _tail = new Data( cast(E[]) arr );
        }
    }

    /// Construct an appender with a capacity of at least N elements.
    this(size_t N) {
        if(__ctfe) {
            _ctfe_array = new T[0];
        } else {
            _head = _tail = new Data( N * T.sizeof );
        }
    }

    /// Returns: a mutable copy of the data.
    E[] dup()  {
        if(__ctfe) return _ctfe_array.dup;
        return _head !is _tail ? flatten : flatten.dup;
    }

    /// Returns: a immutable copy of the data.
    immutable(E)[] idup() {
        return cast(immutable(E)[]) dup;
    }

    /// Returns: the appender's data as an array.
    T[] data() {
        if(__ctfe) return _ctfe_array;

        auto arr = flatten;
        if(_head !is _tail) {
            *_head = arr;
             _tail = _head;
        }
        return cast(T[]) arr;
    }

    /// Returns: the number of elements that can be added before allocation.
    size_t slack() {
        if(__ctfe) return _ctfe_array.capacity - _ctfe_array.length;
        return _tail ? _tail.capacity - _tail.arr.length : 0;
    }

    /// Increases the slack by at least N elements
    void extend(size_t N) {
        if(__ctfe) return;

        assert( size_t.max / T.sizeof  >= N, "Capacity overflow.");
        auto size = N * T.sizeof;

        // Initialize if not done so.
        if(_tail) {
            _head = _tail = new Data( size );
            return;
        }

        // Try extending
        if( auto u = GC.extend(_tail.arr.ptr, size, size) ) {
            _tail.capacity = u / T.sizeof;
            return;
        }

        // If full, add a segment
        if(_tail.arr.length == _tail.capacity) {
             _tail.next = new Data( size );
             _tail      = _tail.next;
             return;
        }

        // Allocate & copy
        auto next = Data(size);
        memcpy(next.arr.ptr, _tail.arr.ptr, _tail.arr.length * T.sizeof);
        _tail.arr       = next.arr.ptr[0.._tail.arr.length];
        _tail.capacity  = next.capacity;
    }

    /// Returns: the total number of elements currently allocated.
    size_t capacity() {
        if(__ctfe) return _ctfe_array.capacity;
        size_t cap = 0;
        for(auto d = _head; d !is null; d = d.next)
            cap   += d.capacity;
        return cap;
    }

    /// Ensures that the capacity is a least newCapacity elements.
    void reserve(size_t newCapacity) {
        if(__ctfe) return;
        auto cap  = capacity;
        if(  cap >= newCapacity) return;
        extend( newCapacity - cap );
    }

    /// Appends to the output range
    void put(U)(U item) if ( isOutputRange!(Unqual!T[],U) ){
        if(__ctfe) {
            static if ( __traits(compiles, _ctfe_array ~= item) ) {
                return _ctfe_array ~= item;
            } else {
                .put(cast(immutable(T)[])_ctfe_array, item);
            }
        }
        // put(T)
        static if ( isImplicitlyConvertible!(U, E) ){
            if(!_head)
                _head = _tail  = new Data( 16 * T.sizeof );
            else if( _tail.arr.length == _tail.capacity  ) {   // Try extending
                if( auto u = GC.extend(_tail.arr.ptr, T.sizeof, nextCapacity) )
                     _tail.capacity     = u / T.sizeof;
                else _tail = _tail.next = new Data( nextCapacity );
            }
            auto          len  = _tail.arr.length;
            _tail.arr.ptr[len] = item;
            _tail.arr          = _tail.arr.ptr[0 .. len + 1];

        // fast put(T[])
        } else static if( is(typeof(_tail.arr[0..1] = item[0..1])) ){
            auto items  = cast(E[]) item[];
            if(!_tail)
                _head   = _tail = new Data(  items.length * T.sizeof );
            auto arr    = _tail.arr.ptr[_tail.arr.length.._tail.capacity];
            size_t len  = items.length;
            if(arr.length < len) {                             // Try extending
                auto size  = max(items.length*T.sizeof, nextCapacity);
                if( auto u = GC.extend(_tail.arr.ptr, T.sizeof, size) ) {
                    _tail.capacity = u / T.sizeof;
                    arr    = _tail.arr.ptr[_tail.arr.length.._tail.capacity];
                }
                if(arr.length < len) len = arr.length;
            }
            arr[0..len] = items[0..len];
            items       = items[len..$];
            _tail.arr   = _tail.arr.ptr[0 .. _tail.arr.length + len];
            if( items.length > 0 ) {               // Add a segment and advance
                _tail.next = new Data(max(items.length*T.sizeof,nextCapacity));
                _tail      = _tail.next;
                _tail.arr.ptr[0..items.length] = items[];
                _tail.arr   = _tail.arr.ptr[0..items.length];
            }

        // Everything else
        } else {
            .put!(typeof(this),U,true,Unqual!T)(this,item);
        }
    }
    /// ditto
    typeof(this) opOpAssign(string op, U)(U item)
        if ( op=="~" && isOutputRange!(Unqual!T[],U) )
    {
        put(item);
        return this;
    }

    // only allow overwriting data on non-immutable and non-const data
    static if(!is(T == immutable) && !is(T == const)) {
        /** Clears the managed array. This function may reduce the appender's
         *  capacity.
         *
         * Note that clear is disabled for immutable or const element types, due
         * to the possibility that $(D Appender) might overwrite immutable data.
         */
        void clear() {
            if(__ctfe) {
                _ctfe_array.length = 0;
            } else {
                _head     = _tail;         // Save the largest chunk and move on
                _tail.arr = _tail.arr.ptr[0..0];
            }
        }

        /** Shrinks the appender to a given length. Passing in a length that's
         *  greater than the current array length throws an enforce exception.
         *  This function may reduce the appender's capacity.
         */
        void shrinkTo(size_t newlength) {
            if(__ctfe) {
                _ctfe_array.length = newlength;
            } else {
                for(auto d = _head; d !is null; d = d.next) {
                    if(d.arr.length >= newlength) {
                        d.arr  = d.arr.ptr[0..newlength];
                        d.next = null;
                    }
                    newlength -= d.arr.length;
                }
                enforce(newlength==0,"Appender.shrinkTo: newlength > capacity");
            }
        }
    }

    /// Returns: a forward range iterating over the Appender's content
    auto opSlice() {
        static struct Slice {
            private {
                Data*   node;
                E[]     data;
            }

            alias .ElementType!(T[]) ElementType;

            bool         empty()    { return data.empty; }
            typeof(this) save()     { return this;       }
            ElementType  front()    { return data.front; }
            void         popFront() {
                data.popFront;
                while(empty && node !is null) {
                    node = node.next;
                    if(node !is null)
                        data = node.arr;
                }
            }
        }
        if(__ctfe)          return Slice(null, cast(E[])_ctfe_array);
        if(_head is null)   return Slice(null,null);
                            return Slice(_head, _head.arr);
    }

    /// Returns: the conversion of this[] to type U.
    U opCast(U)() if ( __traits(compiles, .to!U(opSlice) )) {
       return .to!U( this[] );
    }
    ///ditto
    alias opCast to;

    /// Returns: $(D Appender.to!string)
    static if ( __traits(compiles, .to!string(opSlice) )) {
        string toString() {
           return .to!string( this[] );
        }
    }
}