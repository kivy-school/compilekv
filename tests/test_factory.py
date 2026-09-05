"""Generated classes register with the Factory; unknown widgets come off it."""

import ast

EXTERNAL_KV = "<Card@BoxLayout>:\n    SomeExternalThing:\n        text: 'x'\n"


def test_every_generated_class_is_registered(compiler):
    generated = compiler.compile_source("<A@BoxLayout>:\n    x: 1\n\n<B@Label>:\n    y: 2\n")
    assert 'Factory.register("A", cls=A)' in generated
    assert 'Factory.register("B", cls=B)' in generated
    assert "from kivy.factory import Factory" in generated


def test_registration_comes_after_the_class(compiler):
    generated = compiler.compile_source("<A@BoxLayout>:\n    x: 1\n")
    assert generated.index("class A(") < generated.index("Factory.register")


def test_an_existing_registration_is_not_repeated(compiler):
    existing = (
        "from kivy.uix.boxlayout import BoxLayout\n"
        "from kivy.factory import Factory\n\n"
        "class Card(BoxLayout):\n    pass\n\n"
        "Factory.register('Card', cls=Card)\n"
    )
    generated = compiler.compile_source("<Card@BoxLayout>:\n    x: 1\n", existing)
    assert generated.count("Factory.register") == 1
    assert generated.count("from kivy.factory import Factory") == 1


def test_registering_is_idempotent(compiler):
    once = compiler.compile_source("<Card@BoxLayout>:\n    x: 1\n")
    twice = compiler.compile_source("<Card@BoxLayout>:\n    x: 1\n", once)
    assert twice.count("Factory.register") == 1


def test_an_unknown_widget_comes_off_the_factory(compiler):
    generated = compiler.compile_source(EXTERNAL_KV)
    assert "SomeExternalThing = Factory.SomeExternalThing" in generated
    assert "from kivy.uix.someexternalthing import" not in generated


def test_the_factory_constant_is_callable_not_a_type_alias(compiler):
    """`type X = Factory.X` would be lazy but a TypeAliasType is not callable."""
    generated = compiler.compile_source(EXTERNAL_KV)
    assert "type SomeExternalThing" not in generated
    assert "SomeExternalThing(text=" in generated


def test_a_known_kivy_widget_is_still_imported(compiler):
    generated = compiler.compile_source("<Card@BoxLayout>:\n    Label:\n        text: 'x'\n")
    assert "from kivy.uix.label import Label" in generated
    assert "Label = Factory.Label" not in generated


def test_no_factory_constant_when_the_author_supplies_the_name(compiler):
    generated = compiler.compile_source(EXTERNAL_KV, "from mylib import SomeExternalThing\n")
    assert "SomeExternalThing = Factory.SomeExternalThing" not in generated
    assert "from mylib import SomeExternalThing" in generated


def test_a_widget_defined_by_another_rule_is_not_a_factory_constant(compiler):
    kv = "<MyButton@Button>:\n    text: 'a'\n\n<Card@BoxLayout>:\n    MyButton:\n        text: 'b'\n"
    generated = compiler.compile_source(kv)
    assert "MyButton = Factory.MyButton" not in generated
    assert "class MyButton(Button):" in generated


def test_a_class_in_the_existing_python_is_not_a_factory_constant(compiler):
    existing = "from kivy.uix.button import Button\n\nclass MyButton(Button):\n    pass\n"
    kv = "<Card@BoxLayout>:\n    MyButton:\n        text: 'b'\n"
    generated = compiler.compile_source(kv, existing)
    assert "MyButton = Factory.MyButton" not in generated


def test_the_result_stays_valid_python(compiler):
    ast.parse(compiler.compile_source(EXTERNAL_KV))
