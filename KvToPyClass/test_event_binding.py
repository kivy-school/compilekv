from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.uix.mybutton import MyButton
from kivy.uix.textinput import TextInput


class UserProfile(BoxLayout):

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._bindings = []
        self.orientation = "vertical"
        self.spacing = 10.0
        self.padding = 20.0
        label_63CA62FF = Label(text="User Profile", font_size=24.0, size_hint_y=None, height=40.0)
        self.add_widget(label_63CA62FF)
        box_2C88C0FF = BoxLayout(orientation="horizontal", spacing=10.0)
        label_F9F01180 = Label(text="Name:", size_hint_x=0.3)
        box_2C88C0FF.add_widget(label_F9F01180)
        name_input = TextInput(multiline=False)
        self.ids.name_input = name_input
        box_2C88C0FF.add_widget(name_input)
        self.add_widget(box_2C88C0FF)
        box_4AA757E4 = BoxLayout(orientation="horizontal", spacing=10.0)
        label_8BCAC544 = Label(text="Email:", size_hint_x=0.3)
        box_4AA757E4.add_widget(label_8BCAC544)
        email_input = TextInput(multiline=False)
        self.ids.email_input = email_input
        box_4AA757E4.add_widget(email_input)
        self.add_widget(box_4AA757E4)
        mybutton_555FAFB4 = MyButton(text="Save Profile")
        _callback_0 = lambda instance: self.save_profile()
        mybutton_555FAFB4.bind(on_press=_callback_0)
        self.add_widget(mybutton_555FAFB4)
        self._bindings.append((mybutton_555FAFB4, "on_press", _callback_0))

    def __del__(self):
        for (obj, prop, callback) in self._bindings:
            try:
                obj.unbind(**{prop: callback})
            except:
                pass