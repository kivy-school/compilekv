"""A visible end to end round trip.

Runs last and prints both inputs and the generated output, so a test run shows
what the wasm module actually does rather than only asserting about it. Printing
bypasses pytest's capture, so it shows without `-s`.
"""

from compilekv import compile_file

# A rule with children, a property binding and an event handler, so the
# generated class exercises most of the generator.
DEMO_KV = """\
<ProfileCard@BoxLayout>:
    orientation: 'vertical'
    spacing: 10
    Label:
        text: app.user_name
        font_size: 24
    Button:
        text: 'Save'
        on_press: self.save()
"""

# An existing file with a hand written method the generator must carry over.
DEMO_PY = '''\
class ProfileCard(BoxLayout):

    def save(self):
        """Hand written -- must survive regeneration."""
        print("saving", self.ids)
'''

WIDTH = 72


def _banner(label: str) -> str:
    return f"\n{'─' * WIDTH}\n {label}\n{'─' * WIDTH}"


def test_round_trip_is_visible(tmp_path, compiler, capsys):
    kv = tmp_path / "profile_card.kv"
    kv.write_text(DEMO_KV)
    existing = tmp_path / "profile_card.py"
    existing.write_text(DEMO_PY)

    target = compile_file(kv, compiler=compiler)
    generated = target.read_text()

    with capsys.disabled():
        print(_banner("INPUT  profile_card.kv"))
        print(DEMO_KV)
        print(_banner("INPUT  profile_card.py  (existing, hand written)"))
        print(DEMO_PY)
        print(_banner("OUTPUT  profile_card.py  (generated)"))
        print(generated)

    # The hand written method survives, exactly once.
    assert generated.count("def save(self):") == 1
    assert "Hand written" in generated
    # The generated members are there too.
    assert generated.count("def __init__") == 1
    assert generated.count("def __del__") == 1
    # And a second pass changes nothing.
    compile_file(kv, compiler=compiler)
    assert target.read_text() == generated
