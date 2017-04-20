/**
 * Created by milan on 20/04/17.
 */

var searchFriend = new Vue({
    el: '#my-friend-list',

    data: {
      apiURL: "https://forgotmygarmin.com/friends/find",
      loader: false,
      search: "",
      data: [],
      page: 1,
      pages: 1,
      error: {
        message: ""
      }
    },

    created: function () {
      this.getFriends(1)
    },

    methods: {
      onSearchChange: _.debounce(function () {
        this.getFriends(1)
      }, 500),

      getFriends: function (page) {
        var that = this;
        if (this.search && this.search != "") {
          var url = that.apiURL + "?q=" + this.search;

          if (page > 1) {
            url = url + "&page=" + page
          }

          that.loader = true;
          that.$http.get(url)
            .then(function (result) {
              that.loader = false;
              data = result.data;
              that.page = parseInt(data.page);
              that.pages = parseInt(data.pages);
              that.data = data.results;
            }, function (response, status, request) {
              that.loader = false;
              var data = response.data;
              if (data.message) {
                that.error.message = data.message;
              }
              else {
                that.error.message = "Oops Something went wrong, please try again later.";
              }
            })
            .finally(function () {
            });
        } else {
          that.page = 1;
          that.pages = 1;
          that.data = [];
        }
      },
      getPages: function () {
        var arr = [];

        for (var i = 1; i <= this.pages; i++) {
          var page = {
            text: "page" + i,
            id: i,
            current: false
          };
          if (i == this.page) {
            page.current = true;
          }
          arr.push(page)
        }

        return arr;
      }
    }
  })
  ;
