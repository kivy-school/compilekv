from kivy.uix.widget import Widget
from kivy.graphics import Color, Rectangle


class SimpleCanvas(Widget):

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._bindings = []
        self.canvas.add(Color(rgb=(1.0, 0.0, 0.0)))
        self._canvas_rectangle_00A310AD = Rectangle()
        self.canvas.add(self._canvas_rectangle_00A310AD)
        self._canvas_rectangle_00A310AD.pos = self.pos
        _callback_1 = lambda instance, value: setattr(self._canvas_rectangle_00A310AD, "pos", instance)
        self.bind(pos=_callback_1)
        self._canvas_rectangle_00A310AD.size = self.size
        _callback_2 = lambda instance, value: setattr(self._canvas_rectangle_00A310AD, "size", instance)
        self.bind(size=_callback_2)
        self._bindings.append((self, "pos", _callback_1))
        self._bindings.append((self, "size", _callback_2))

    def __del__(self):
        for (obj, prop, callback) in self._bindings:
            try:
                obj.unbind(**{prop: callback})
            except:
                pass