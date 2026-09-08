from kivy.uix.boxlayout import BoxLayout
from kivy.uix.widget import Widget
from kivy.app import App
from kivy.graphics import Color, Ellipse, Line, PopMatrix, PushMatrix, Rectangle, Rotate


class MyCanvasWidget(BoxLayout):

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._bindings = []
        self.canvas.before.add(Color(rgba=(0.2, 0.2, 0.2, 1.0)))
        self._canvas_rectangle_504605F6 = Rectangle()
        self.canvas.before.add(self._canvas_rectangle_504605F6)
        self._canvas_rectangle_504605F6.pos = self.pos
        _callback_1 = lambda instance, value: setattr(self._canvas_rectangle_504605F6, "pos", value)
        self.bind(pos=_callback_1)
        self._canvas_rectangle_504605F6.size = self.size
        _callback_2 = lambda instance, value: setattr(self._canvas_rectangle_504605F6, "size", value)
        self.bind(size=_callback_2)
        self.canvas.add(Color(rgb=(1.0, 0.0, 0.0)))
        self._canvas_ellipse_916FF6CA = Ellipse(size=(100.0, 100.0))
        self.canvas.add(self._canvas_ellipse_916FF6CA)
        self._canvas_ellipse_916FF6CA.pos = ((self.x + 50), (self.y + 50))
        _callback_3 = lambda instance, value: setattr(self._canvas_ellipse_916FF6CA, "pos", ((instance.x + 50), (instance.y + 50)))
        self.bind(x=_callback_3)
        _callback_4 = lambda instance, value: setattr(self._canvas_ellipse_916FF6CA, "pos", ((instance.x + 50), (instance.y + 50)))
        self.bind(y=_callback_4)
        self.canvas.add(Color(rgba=(0.0, 1.0, 0.0, 0.5)))
        self._canvas_line_61118867 = Line(width=2.0)
        self.canvas.add(self._canvas_line_61118867)
        self._canvas_line_61118867.points = [self.x, self.y, self.right, self.top]
        _callback_5 = lambda instance, value: setattr(self._canvas_line_61118867, "points", [instance.x, instance.y, instance.right, instance.top])
        self.bind(x=_callback_5)
        _callback_6 = lambda instance, value: setattr(self._canvas_line_61118867, "points", [instance.x, instance.y, instance.right, instance.top])
        self.bind(y=_callback_6)
        _callback_7 = lambda instance, value: setattr(self._canvas_line_61118867, "points", [instance.x, instance.y, instance.right, instance.top])
        self.bind(right=_callback_7)
        _callback_8 = lambda instance, value: setattr(self._canvas_line_61118867, "points", [instance.x, instance.y, instance.right, instance.top])
        self.bind(top=_callback_8)
        self.canvas.after.add(PushMatrix())
        self._canvas_rotate_C98B4A6C = Rotate(angle=45.0)
        self.canvas.after.add(self._canvas_rotate_C98B4A6C)
        self._canvas_rotate_C98B4A6C.origin = self.center
        _callback_9 = lambda instance, value: setattr(self._canvas_rotate_C98B4A6C, "origin", value)
        self.bind(center=_callback_9)
        self.canvas.after.add(Color(rgb=(0.0, 0.0, 1.0)))
        self._canvas_rectangle_FF8B70BE = Rectangle(size=(50.0, 50.0))
        self.canvas.after.add(self._canvas_rectangle_FF8B70BE)
        self._canvas_rectangle_FF8B70BE.pos = ((self.center_x - 25), (self.center_y - 25))
        _callback_10 = lambda instance, value: setattr(self._canvas_rectangle_FF8B70BE, "pos", ((instance.center_x - 25), (instance.center_y - 25)))
        self.bind(center_x=_callback_10)
        _callback_11 = lambda instance, value: setattr(self._canvas_rectangle_FF8B70BE, "pos", ((instance.center_x - 25), (instance.center_y - 25)))
        self.bind(center_y=_callback_11)
        self.canvas.after.add(PopMatrix())
        self._bindings.append((self, "pos", _callback_1))
        self._bindings.append((self, "size", _callback_2))
        self._bindings.append((self, "x", _callback_3))
        self._bindings.append((self, "y", _callback_4))
        self._bindings.append((self, "x", _callback_5))
        self._bindings.append((self, "y", _callback_6))
        self._bindings.append((self, "right", _callback_7))
        self._bindings.append((self, "top", _callback_8))
        self._bindings.append((self, "center", _callback_9))
        self._bindings.append((self, "center_x", _callback_10))
        self._bindings.append((self, "center_y", _callback_11))

    def __del__(self):
        for (obj, prop, callback) in self._bindings:
            try:
                obj.unbind(**{prop: callback})
            except:
                pass




class MyDrawingWidget(Widget):

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._bindings = []
        app = App.get_running_app()
        self._canvas_color_A29BE994 = Color()
        self.canvas.add(self._canvas_color_A29BE994)
        self._canvas_color_A29BE994.rgba = app.bg_color if hasattr(app, "bg_color") else (1, 1, 1, 1)
        _callback_1 = lambda instance, value: setattr(self._canvas_color_A29BE994, "rgba", app.bg_color if hasattr(app, "bg_color") else (1, 1, 1, 1))
        app.bind(bg_color=_callback_1)
        self._canvas_rectangle_FDE5AC3C = Rectangle()
        self.canvas.add(self._canvas_rectangle_FDE5AC3C)
        self._canvas_rectangle_FDE5AC3C.pos = self.pos
        _callback_2 = lambda instance, value: setattr(self._canvas_rectangle_FDE5AC3C, "pos", value)
        self.bind(pos=_callback_2)
        self._canvas_rectangle_FDE5AC3C.size = self.size
        _callback_3 = lambda instance, value: setattr(self._canvas_rectangle_FDE5AC3C, "size", value)
        self.bind(size=_callback_3)
        self.canvas.add(Color(rgb=(1.0, 1.0, 0.0)))
        self._canvas_ellipse_5EEADB71 = Ellipse(size=(40.0, 40.0))
        self.canvas.add(self._canvas_ellipse_5EEADB71)
        self._canvas_ellipse_5EEADB71.pos = ((self.center_x - 20), (self.center_y - 20))
        _callback_4 = lambda instance, value: setattr(self._canvas_ellipse_5EEADB71, "pos", ((instance.center_x - 20), (instance.center_y - 20)))
        self.bind(center_x=_callback_4)
        _callback_5 = lambda instance, value: setattr(self._canvas_ellipse_5EEADB71, "pos", ((instance.center_x - 20), (instance.center_y - 20)))
        self.bind(center_y=_callback_5)
        self._bindings.append((app, "bg_color", _callback_1))
        self._bindings.append((self, "pos", _callback_2))
        self._bindings.append((self, "size", _callback_3))
        self._bindings.append((self, "center_x", _callback_4))
        self._bindings.append((self, "center_y", _callback_5))

    def __del__(self):
        for (obj, prop, callback) in self._bindings:
            try:
                obj.unbind(**{prop: callback})
            except:
                pass