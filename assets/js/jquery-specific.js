function loadList() {
  //document.getElementById("content").innerHTML='<object type="text/html" data="assets/list.html" ></object>';
  $.ajax({
      url: "assets/list.html",
      success: function (data) {
        $('#content').children().remove();
        $('#content').append(data); 
      },
      dataType: 'html'
  });
}
