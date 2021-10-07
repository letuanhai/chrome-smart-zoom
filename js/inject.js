// https://stackoverflow.com/questions/12098327/how-to-add-dbclick-on-right-click-in-jquery
function makeDoubleRightClickHandler(handler) {
    var timeout = 0, clicked = false;
    return function (e) {
        if (clicked) {
            e.preventDefault(); // Only prevent context menu on double right click
            clearTimeout(timeout);
            clicked = false;
            return handler.apply(this, arguments);
        }
        else {
            clicked = true;
            timeout = setTimeout(function () {
                clicked = false;
            }, 300);
        }
    };
};

document.querySelector('body')
    .addEventListener('contextmenu', makeDoubleRightClickHandler(
        function (event) {
            zoom.to({ element: event.target });
        }));