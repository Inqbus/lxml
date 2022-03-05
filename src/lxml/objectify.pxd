
from lxml.includes.etreepublic cimport ElementBase

from lxml.includes.etreepublic cimport _Element

cdef class ObjectifiedElement(ElementBase):
    pass

cdef _appendValue(_Element parent, tag, value)

cdef _replaceElement(_Element element, value)

cdef _setSlice(sliceobject, _Element target, items)

cdef object _lookupChildOrRaise(_Element parent, tag)

cdef inline object _buildChildTag(_Element parent, tag)
