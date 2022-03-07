# cython: binding=True
# cython: auto_pickle=False
# cython: language_level=2

"""
The ``lxml.objectify2`` module implements a Python object API for XML.
It is based on `lxml.etree`.
"""

from __future__ import absolute_import

cimport lxml.includes.etreepublic as cetree
from lxml cimport python
from lxml.includes cimport tree
from lxml.includes.etreepublic cimport ( _Element, elementFactory,
                                        import_lxml__etree, pyunicode)
from lxml.includes.tree cimport _xcstr, const_xmlChar

from lxml.objectify cimport ObjectifiedElement

from lxml.objectify cimport _appendValue, _replaceElement, _setSlice

from lxml.objectify cimport _typename, _buildChildTag

from lxml.includes.etreepublic cimport ElementBase

cdef object etree
from lxml import etree
# initialize C-API of lxml.etree
import_lxml__etree()

__version__ = etree.__version__

cdef object _float_is_inf, _float_is_nan

cdef object re
import re

cdef tuple IGNORABLE_ERRORS = (ValueError, TypeError)
cdef object is_special_method = re.compile(u'__.*__$').match

cdef object _parse
_parse = etree.parse

class NoUnderscoreTag(Exception):
    pass


cdef class Qtag():

    name = None
    namespace = None

    def __init__(self, namespace, name):
        self.namespace = namespace
        self.name = name

    @property
    def cl(self):
        return '{' + self.namespace + '}' + self.name

    @property
    def u(self):
        return self.namespace + '_' + self.name

    @classmethod
    def from_utag(cls, u_tag):
        split_utag = u_tag.split('_')
        if len(split_utag) == 1:
            namespace = None
            name = u_tag
        else:
            ns_prefix, name  = split_utag[0], ' '.join(split_utag[1])
        return cls(ns_prefix, name)

    @classmethod
    def from_cltag(cls, cl_tag):
        namespace, name  = ns_name_from_clarke(cl_tag)
        return cls(namespace, name)

# Switch for lookup mode for non qualified tags
# Work like lxml.objectify (lookup tag in parent namespace)
MODE_LEGACY = 0
# If tag is found once in the list of children return it, else raise AttributeError
MODE_STRICT = 1
# If tag is found once in the list of children return it, else return list of matching childs
MODE_LIST = 2

cdef int _lookup_mode[1]  # storage  'lookup_mode'
_lookup_mode[0] = MODE_LEGACY # default to legacy

# C getter/setter
cdef int*  _get_lookup_mode(): return _lookup_mode
cdef void* _set_lookup_mode(int i): _lookup_mode[0]=i

# Python getter/setter
def get_lookup_mode():
    return _get_lookup_mode()[0]

def set_lookup_mode(mode):
    _set_lookup_mode(mode)


cdef class ObjectifiedElement2(ObjectifiedElement):

    @property
    def __lookup_mode__(self):
        return _get_lookup_mode()[0]

    @__lookup_mode__.setter
    def __lookup_mode__(self, int mode):
        _set_lookup_mode(mode)

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
            u_tag = '{}_{}'.format(prefix, name)
            if u_tag not in children:
                children[u_tag] = child
        return children

    def prefix_and_name_from_utag(self, u_tag):
        """
        Split a q_tag in ns-prefix and name
        """
        split_tag = u_tag.split('_')
        if len(split_tag) == 1:
            # check if we have an default namespace
#            print(self.nsmap)
            if None in self.nsmap:
               return None, u_tag
            # We have a not qualified tag
            raise \
                AttributeError("Tag '{}' has no prefix, nor is a default namespace defined".format(u_tag))
        return split_tag[0], '_'.join(split_tag[1:])

    def ns_and_name_from_utag(self, u_tag):
        """
        Split a q_tag in namespace and name
        """
        prefix, name = self.prefix_and_name_from_utag(u_tag)
        namespace = self.nsmap[prefix]
        return namespace, name

    def clarke_from_utag(self, u_tag):
        """
        Convert a q_tag to Clarke notation
        """
        prefix, name = self.prefix_and_name_from_utag(u_tag)

        try:
            namespace = self.nsmap[prefix]
        except KeyError as e:
            return '{}' + name

        cl_tag = '{' + namespace + '}' + name
        return cl_tag

    def __getattr__(self, u_tag):
        u"""Return the (first) child with the given tag name.  If no namespace
        is provided, the child will be looked up in the same one as self.
        """
        if is_special_method(u_tag):
            return object.__getattribute__(self, u_tag)

        # If we already have a clarke notated tag
        if u_tag[0] == '{':
            return _lookupChildOrRaise(self, u_tag)

        cl_tag = self.clarke_from_utag(u_tag)
        return _lookupChildOrRaise(self, cl_tag)


    def __setattr__(self, tag, value):
        u"""Set the value of the (first) child with the given tag name.  If no
        namespace is provided, the child will be looked up in the same one as
        self.
        """
        cdef _Element element
        # properties are looked up /after/ __setattr__, so we must emulate them
        if tag == u'text' or tag == u'pyval':
            # read-only !
            raise TypeError, f"attribute '{tag}' of '{_typename(self)}' objects is not writable"
        elif tag == u'tail':
            cetree.setTailText(self._c_node, value)
            return
        elif tag == u'tag':
            ElementBase.tag.__set__(self, value)
            return
        elif tag == u'base':
            ElementBase.base.__set__(self, value)
            return
        cl_tag = self.clarke_from_utag(tag)
        tag = _buildChildTag(self, cl_tag)
        element = _lookupChild(self, tag)
        if element is None:
            _appendValue(self, tag, value)
        else:
            _replaceElement(element, value)

    def __delattr__(self, u_tag):
        child = self.__getattr__(u_tag)
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
            element = self.__getattr__(key)
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


    def addattr(self, q_tag, value):
        u"""addattr(self, tag, value)

        Add a child value to the element.

        As opposed to append(), it sets a data value, not an element.
        """
        ns_tag = self.clarke_from_utag(q_tag)
        _appendValue(self, ns_tag, value)



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
        return ''

    return split_tag[0][1:], split_tag[1]


cdef object _lookupChildOrRaise(_Element parent, tag):
    element = _lookupChild(parent, tag)
    if element is None:
        raise AttributeError, u"no such child: " + tag
    return element


cdef object _lookupChild(_Element parent, cl_tag):
    cdef tree.xmlNode* c_result
    cdef tree.xmlNode* c_node

    result = ns_name_from_clarke(cl_tag)
    namespace, name = result

    c_node = parent._c_node
    c_name = bytes(name.encode('utf-8'))

    c_tag = tree.xmlDictExists(
        c_node.doc.dict, _xcstr(c_name), python.PyBytes_GET_SIZE(c_name))

    if c_tag is NULL:
        return None # not in the hash map => not in the tree

    if namespace is None:
        c_result = _findFollowingSibling(c_node.children, NULL, c_tag, 0)
    else:
        c_namespace = bytes(namespace.encode('utf-8'))
        c_result = _findFollowingSibling(c_node.children, c_namespace, c_tag, 0)

#    print('_lookupChild cl_tag {}'.format(cl_tag))
    if c_result is NULL:
#        print('_lookupChild cl_tag {} failed'.format(cl_tag))
        return None
#    print('_lookupChild cl_tag {} ok'.format(cl_tag))
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



