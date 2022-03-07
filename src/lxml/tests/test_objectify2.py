# -*- coding: utf-8 -*-

"""
Tests specific to the lxml.objectify API
"""

from __future__ import absolute_import

import operator
from functools import partial

from lxml.objectify2 import ObjectifiedElement2

from lxml.tests.test_objectify import ObjectifyTestCase, xml_str
from .common_imports import etree

from lxml import objectify


class Objectify2TestCase(ObjectifyTestCase):
    """Test cases for lxml.objectify
    """
    etree = etree
    
    def XML(self, xml):
        return self.etree.XML(xml, self.parser)

    def setUp(self):
        super(Objectify2TestCase, self).setUp()
        self.parser = self.etree.XMLParser(remove_blank_text=True)
        self.lookup = etree.ElementNamespaceClassLookup(
            objectify.ObjectifyElementClassLookup(tree_class=ObjectifiedElement2) )
        self.parser.set_element_class_lookup(self.lookup)
        self.Element = partial(self.parser.makeelement, nsmap={None:'noprefix'})

        ns = self.lookup.get_namespace("otherNS")
        ns[None] = self.etree.ElementBase

        self._orig_types = objectify.getRegisteredTypes()

    def test_addattr(self):
        root = self.XML(xml_str)
        self.assertEqual(1, len(root.obj_c1))
        root.addattr("obj_c1", "test")
        self.assertEqual(2, len(root.obj_c1))
        self.assertEqual("test", root.obj_c1[1].text)

    def test_addattr_list(self):
        root = self.XML(xml_str)
        self.assertEqual(1, len(root.obj_c1))

        new_el = self.Element("test")
        self.etree.SubElement(new_el, "a", myattr="A")
        self.etree.SubElement(new_el, "a", myattr="B")


        root.addattr("obj_c1", list(new_el.obj_a))
        self.assertEqual(3, len(root.obj_c1))
        self.assertEqual(None, root.obj_c1[0].get("myattr"))
        self.assertEqual("A",  root.obj_c1[1].get("myattr"))
        self.assertEqual("B",  root.obj_c1[2].get("myattr"))

    def test_addattr_element(self):
        root = self.XML(xml_str)
        self.assertEqual(1, len(root.obj_c1))

        new_el = self.Element("test", myattr="5")
        root.addattr("obj_c1", new_el)
        self.assertEqual(2, len(root.obj_c1))
        self.assertEqual(None, root.obj_c1[0].get("myattr"))
        self.assertEqual("5",  root.obj_c1[1].get("myattr"))

    def test_build_tree(self):
        root = self.Element('root')
        root.a = 5
        root.b = 6
        self.assertTrue(isinstance(root, objectify.ObjectifiedElement))
        self.assertTrue(isinstance(root.a, objectify.IntElement))
        self.assertTrue(isinstance(root.b, objectify.IntElement))


    def test_child(self):
        root = self.XML(xml_str)
        self.assertEqual("0", root.obj_c1.obj_c2.text)

    def test_child_addattr(self):
        root = self.XML(xml_str)
        self.assertEqual(3, len(root.obj_c1.obj_c2))
        root.obj_c1.addattr("obj_c2", 3)
        self.assertEqual(4, len(root.obj_c1.obj_c2))
        self.assertEqual("3", root.obj_c1.obj_c2[3].text)

    def test_child_index(self):
        root = self.XML(xml_str)
        self.assertEqual("0", root.obj_c1.obj_c2[0].text)
        self.assertEqual("1", root.obj_c1.obj_c2[1].text)
        self.assertEqual("2", root.obj_c1.obj_c2[2].text)
        self.assertRaises(IndexError, operator.getitem, root.obj_c1.obj_c2, 3)
        self.assertEqual(root, root[0])
        self.assertRaises(IndexError, operator.getitem, root, 1)

    def test_child_getattr(self):
        root = self.XML(xml_str)
        self.assertEqual("0", getattr(root.obj_c1, "{objectified}c2").text)
        self.assertEqual("3", getattr(root.obj_c1, "{otherNS}c2").text)
        self.assertEqual("0", getattr(root.obj_c1, "obj_c2").text)
        self.assertEqual("3", getattr(root.obj_c1, "other_c2").text)

    def test_child_getattr_empty_ns(self):
        root = self.XML(xml_str)
        self.assertEqual("4", getattr(root.obj_c1, "{}c2").text)
        self.assertEqual("0", getattr(root.obj_c1, "obj_c2").text)

    def test_child_index_neg(self):
        root = self.XML(xml_str)
        self.assertEqual("0", root.obj_c1.obj_c2[0].text)
        self.assertEqual("0", root.obj_c1.obj_c2[-3].text)
        self.assertEqual("1", root.obj_c1.obj_c2[-2].text)
        self.assertEqual("2", root.obj_c1.obj_c2[-1].text)
        self.assertRaises(IndexError, operator.getitem, root.obj_c1.obj_c2, -4)
        self.assertEqual(root, root[-1])
        self.assertRaises(IndexError, operator.getitem, root, -2)

        c1 = root.obj_c1
        del root.obj_c1  # unlink from parent
        self.assertEqual(c1, c1[-1])
        self.assertRaises(IndexError, operator.getitem, c1, -2)

    def test_child_len(self):
        root = self.XML(xml_str)
        self.assertEqual(1, len(root))
        self.assertEqual(1, len(root.obj_c1))
        self.assertEqual(3, len(root.obj_c1.obj_c2))

    def test_child_iter(self):
        root = self.XML(xml_str)
        self.assertEqual([root],
                          list(iter(root)))
        self.assertEqual([root.obj_c1],
                          list(iter(root.obj_c1)))
        self.assertEqual([root.obj_c1.obj_c2[0], root.obj_c1.obj_c2[1], root.obj_c1.obj_c2[2]],
                         list(iter(root.obj_c1.obj_c2)))

    def test_child_nonexistant(self):
        root = self.XML(xml_str)
        self.assertRaises(AttributeError, getattr, root.obj_c1, "NOT_THERE")
        self.assertRaises(AttributeError, getattr, root.obj_c1, "{unknownNS}c2")

    def test_child_ns_nons(self):
        root = self.XML("""
            <root>
                <foo:x xmlns:foo="/foo/bar">1</foo:x>
                <x>2</x>
            </root>
        """)
        self.assertEqual(2, root.foo_x)

    def test_child_set_ro(self):
        root = self.XML(xml_str)
        self.assertRaises(TypeError, setattr, root.obj_c1.obj_c2, 'text',  "test")
        self.assertRaises(TypeError, setattr, root.obj_c1.obj_c2, 'pyval', "test")

    def test_class_lookup(self):
        root = self.XML(xml_str)
        self.assertTrue(isinstance(root.obj_c1.obj_c2, objectify.ObjectifiedElement))
        self.assertFalse(isinstance(getattr(root.obj_c1, "{otherNS}c2"),
                                    objectify.ObjectifiedElement))

    def test_countchildren(self):
        root = self.XML(xml_str)
        self.assertEqual(1, root.countchildren())
        self.assertEqual(5, root.obj_c1.countchildren())

    def test_child_getattr(self):
        root = self.XML(xml_str)
        self.assertEqual("0", getattr(root.obj_c1, "{objectified}c2").text)
        self.assertEqual("3", getattr(root.obj_c1, "{otherNS}c2").text)

    def test_child_nonexistant(self):
        root = self.XML(xml_str)
        self.assertRaises(AttributeError, getattr, root.obj_c1, "NOT_THERE")
        self.assertRaises(AttributeError, getattr, root.obj_c1, "{unknownNS}c2")

    def test_child_getattr_empty_ns(self):
        root = self.XML(xml_str)
        self.assertEqual("4", getattr(root.obj_c1, "{}c2").text)
        self.assertEqual("0", getattr(root.obj_c1, "obj_c2").text)



if __name__ == '__main__':
    print('to test use test.py %s' % __file__)
