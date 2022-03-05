# cython: binding=True
# cython: auto_pickle=False
# cython: language_level=2

"""
The ``lxml.objectify`` module implements a Python object API for XML.
It is based on `lxml.etree`.
"""

from __future__ import absolute_import

cimport cython
cimport libc.string as cstring_h  # not to be confused with stdlib 'string'
cimport lxml.includes.etreepublic as cetree
from libc.string cimport const_char
from lxml cimport python
from lxml.includes cimport tree
from lxml.includes.etreepublic cimport (ElementBase, ElementClassLookup,
                                        _Document, _Element, elementFactory,
                                        import_lxml__etree, pyunicode, textOf)
from lxml.includes.tree cimport _xcstr, const_xmlChar

from lxml.objectify cimport ObjectifiedElement

from lxml.objectify cimport _appendValue, _replaceElement, _setSlice, _lookupChildOrRaise, _buildChildTag


cdef object etree
from lxml import etree
# initialize C-API of lxml.etree
import_lxml__etree()

__version__ = etree.__version__

cdef object _float_is_inf, _float_is_nan
from math import isinf as _float_is_inf, isnan as _float_is_nan

cdef object re
import re

cdef tuple IGNORABLE_ERRORS = (ValueError, TypeError)
cdef object is_special_method = re.compile(u'__.*__$').match

cdef object _parse
_parse = etree.parse


cdef class ObjectifiedElement2(ObjectifiedElement):

    @property
    def __dict__(self):
        """Implementation for __dict__ to support dir() etc.

        Return all lxml children a members in <ns-prefix>_<name> aka q_tag notation
        """
        cdef _Element child
        cdef dict children
        children = {}
        for child in etree.ElementChildIterator(self):
            prefix = pyunicode(child._c_node.ns.prefix)
            name = pyunicode(child._c_node.name)
            q_tag = '{}_{}'.format(prefix, name)
            if q_tag not in children:
                children[q_tag] = child
        return children

    def prefix_and_name_from_qtag(self, q_tag):
        """
        Split a q_tag in ns-prefix and name
        """
        split_tag = q_tag.split('_')
        return split_tag[0], '_'.join(split_tag[1:])

    def ns_and_name_from_qtag(self, q_tag):
        """
        Split a q_tag in namespace and name
        """
        prefix, name = self.prefix_and_name_from_qtag(q_tag)
        namespace = self.nsmap[prefix]
        return namespace, name

    def clarke_from_qtag(self, q_tag):
        """
        Convert a q_tag to Clarke notation
        """
        prefix, name = self.prefix_and_name_from_qtag(q_tag)

        try:
            namespace = self.nsmap[prefix]
        except KeyError as e:
            return name

        res = '{' + namespace + '}' + name
        return res

    def __getattr__(self, tag):
        u"""Return the (first) child with the given tag name.  If no namespace
        is provided, the child will be looked up in the same one as self.
        """
        if is_special_method(tag):
            return object.__getattribute__(self, tag)

        ns_tag = self.clarke_from_qtag(tag)
        return _lookupChildOrRaise(self, ns_tag)

    # def __setattr__(self, tag, value):
    #     u"""Set the value of the (first) child with the given tag name.  If no
    #     namespace is provided, the child will be looked up in the same one as
    #     self.
    #     """
    #     cdef _Element element
    #     # properties are looked up /after/ __setattr__, so we must emulate them
    #     if tag == u'text' or tag == u'pyval':
    #         # read-only !
    #         raise TypeError, f"attribute '{tag}' of '{_typename(self)}' objects is not writable"
    #     elif tag == u'tail':
    #         cetree.setTailText(self._c_node, value)
    #         return
    #     elif tag == u'tag':
    #         ElementBase.tag.__set__(self, value)
    #         return
    #     elif tag == u'base':
    #         ElementBase.base.__set__(self, value)
    #         return
    #     tag = _buildChildTag(self, tag)
    #     element = _lookupChild(self, tag)
    #     if element is None:
    #         _appendValue(self, tag, value)
    #     else:
    #         _replaceElement(element, value)

    def __delattr__(self, tag):
        child = _lookupChildOrRaise(self, tag)
        self.remove(child)

    # def addattr(self, tag, value):
    #     u"""addattr(self, tag, value)
    #
    #     Add a child value to the element.
    #
    #     As opposed to append(), it sets a data value, not an element.
    #     """
    #     _appendValue(self, _buildChildTag(self, tag), value)

    def __getitem__(self, key):
        u"""Return a sibling, counting from the first child of the parent.  The
        method behaves like both a dict and a sequence.

        * If argument is an integer, returns the sibling at that position.

        * If argument is a string, does the same as getattr().  This can be
          used to provide namespaces for element lookup, or to look up
          children with special names (``text`` etc.).

        * If argument is a slice object, returns the matching slice.
        """
        cdef tree.xmlNode* c_self_node
        cdef tree.xmlNode* c_parent
        cdef tree.xmlNode* c_node
        cdef Py_ssize_t c_index

        if python._isString(key):
            return _lookupChildOrRaise(self, key)
        elif isinstance(key, slice):
            return list(self)[key]
        # normal item access
        c_index = key   # raises TypeError if necessary
        c_self_node = self._c_node
        c_parent = c_self_node.parent
        if c_parent is NULL:
            if c_index == 0 or c_index == -1:
                return self
            raise IndexError, unicode(key)
        if c_index < 0:
            c_node = c_parent.last
        else:
            c_node = c_parent.children
        c_node = _findFollowingSibling(
            c_node, tree._getNs(c_self_node), c_self_node.name, c_index)
        if c_node is NULL:
            raise IndexError, unicode(key)
        return elementFactory(self._doc, c_node)

    def __setitem__(self, key, value):
        u"""Set the value of a sibling, counting from the first child of the
        parent.  Implements key assignment, item assignment and slice
        assignment.

        * If argument is an integer, sets the sibling at that position.

        * If argument is a string, does the same as setattr().  This is used
          to provide namespaces for element lookup.

        * If argument is a sequence (list, tuple, etc.), assign the contained
          items to the siblings.
        """
        cdef _Element element
        cdef tree.xmlNode* c_node
        if python._isString(key):
            key = _buildChildTag(self, key)
            element = _lookupChild(self, key)
            if element is None:
                _appendValue(self, key, value)
            else:
                _replaceElement(element, value)
            return

        if self._c_node.parent is NULL:
            # the 'root[i] = ...' case
            raise TypeError, u"assignment to root element is invalid"

        if isinstance(key, slice):
            # slice assignment
            _setSlice(key, self, value)
        else:
            # normal index assignment
            if key < 0:
                c_node = self._c_node.parent.last
            else:
                c_node = self._c_node.parent.children
            c_node = _findFollowingSibling(
                c_node, tree._getNs(self._c_node), self._c_node.name, key)
            if c_node is NULL:
                raise IndexError, unicode(key)
            element = elementFactory(self._doc, c_node)
            _replaceElement(element, value)

    def __delitem__(self, key):
        parent = self.getparent()
        if parent is None:
            raise TypeError, u"deleting items not supported by root element"
        if isinstance(key, slice):
            # slice deletion
            del_items = list(self)[key]
            remove = parent.remove
            for el in del_items:
                remove(el)
        else:
            # normal index deletion
            sibling = self.__getitem__(key)
            parent.remove(sibling)

    def lookup_child(self, tag):
        return _lookupChild(self, tag)


cdef tree.xmlNode* _findFollowingSibling(tree.xmlNode* c_node,
                                         const_xmlChar* ns, const_xmlChar* name,
                                         Py_ssize_t index):
    """
    Find the next matching sibling with 'ns' (href) and 'name' to match. 
    """
    cdef tree.xmlNode* (*next)(tree.xmlNode*)
    if index >= 0:
        next = cetree.nextElement
    else:
        index = -1 - index
        next = cetree.previousElement

    while c_node is not NULL:
        if c_node.type == tree.XML_ELEMENT_NODE :
            if _tagMatches(c_node, ns, name):
                index = index - 1
                if index < 0:
                    return c_node
        c_node = next(c_node)
    return NULL


cdef object ns_name_from_clarke(cl_tag):
    """
    Split a Clarke notated c_tag into ns and name
    """
    split_tag = cl_tag.split('}')
    if len(split_tag) < 2 :
        return None

    return split_tag[0][1:], split_tag[1]


cdef object _lookupChild(_Element parent, tag):
    cdef tree.xmlNode* c_result
    cdef tree.xmlNode* c_node

    result = ns_name_from_clarke(tag)
    if result is None:
        return None

    namespace, name = result

    c_node = parent._c_node
    c_name = bytes(name.encode('utf-8'))
    c_namespace = bytes(namespace.encode('utf-8'))

    c_tag = tree.xmlDictExists(
        c_node.doc.dict, _xcstr(c_name), python.PyBytes_GET_SIZE(c_name))

    if c_tag is NULL:
        return None # not in the hash map => not in the tree

    c_result = _findFollowingSibling(c_node.children, c_namespace, c_tag, 0)
    if c_result is NULL:

        return None
    return elementFactory(parent._doc, c_result)


cdef inline bint _tagMatches(tree.xmlNode* c_node, const_xmlChar* c_href, const_xmlChar* c_name):
    if c_node.name != c_name:
        return 0
    if c_href == NULL:
        return 1
    c_node_href = tree._getNs(c_node)
    if c_node_href == NULL:
        return c_href[0] == c'\0'
    return tree.xmlStrcmp(c_node_href, c_href) == 0