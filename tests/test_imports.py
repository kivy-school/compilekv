"""Nothing is imported from a module that does not exist."""

import ast

import pytest


def imports(compiler, kv, py=""):
    generated = compiler.compile_source(kv, py)
    ast.parse(generated)
    return [l for l in generated.splitlines() if l.startswith(("from ", "import "))]


def test_a_class_defined_by_a_rule_is_not_imported(compiler):
    kv = "<Inner@BoxLayout>:\n    padding: 4\n\n<Outer@BoxLayout>:\n    Inner:\n        padding: 8\n"
    assert not any("inner" in line for line in imports(compiler, kv))


def test_a_class_defined_in_the_python_file_is_not_imported(compiler):
    """CTabHeaderItemLayout lives in the file, so importing it invents a module."""
    py = "from kivy.uix.boxlayout import BoxLayout\n\nclass Inner(BoxLayout):\n    pass\n"
    kv = "<Outer@BoxLayout>:\n    Inner:\n        padding: 8\n"
    lines = imports(compiler, kv, py)
    assert "from kivy.uix.inner import Inner" not in lines
    assert not any("Inner = Factory.Inner" in line for line in lines)


def test_a_class_defined_in_the_python_file_is_not_a_factory_constant(compiler):
    py = "from kivy.uix.boxlayout import BoxLayout\n\nclass Inner(BoxLayout):\n    pass\n"
    kv = "<Outer@BoxLayout>:\n    Inner:\n        padding: 8\n"
    assert "Inner = Factory.Inner" not in compiler.compile_source(kv, py)


@pytest.mark.parametrize(
    "widget,module",
    [
        ("Screen", "kivy.uix.screenmanager"),
        ("ActionButton", "kivy.uix.actionbar"),
        ("TabbedPanelHeader", "kivy.uix.tabbedpanel"),
        ("AccordionItem", "kivy.uix.accordion"),
        ("ColorWheel", "kivy.uix.colorpicker"),
        ("Label", "kivy.uix.label"),
        ("BoxLayout", "kivy.uix.boxlayout"),
    ],
)
def test_widgets_come_from_their_real_module(compiler, widget, module):
    kv = f"<Outer@BoxLayout>:\n    {widget}:\n        opacity: 1\n"
    assert f"from {module} import {widget}" in imports(compiler, kv)


def test_an_unknown_widget_still_goes_through_the_factory(compiler):
    kv = "<Outer@BoxLayout>:\n    FromElsewhere:\n        opacity: 1\n"
    generated = compiler.compile_source(kv)
    assert "FromElsewhere = Factory.FromElsewhere" in generated
    assert "kivy.uix.fromelsewhere" not in generated
