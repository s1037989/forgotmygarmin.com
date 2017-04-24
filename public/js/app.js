/**
 * Created by milan on 20/04/17.
 */

Vue.component('api-data', {
  template: '#api-data',
  
  created: function () { this.getData() },

  data: function () {
    return {
      apiURL: "",
      loader: false,
      search: "",
      data: [],
      page: 1,
      pages: 1,
      error: {
        message: ""
      }
    };
  },

  props: {
    apiurl: {
      type: String,
      required: true
    }
  },
  
  methods: {
    onSearchChange: _.debounce(function () { this.getData('current') }, 500),

    getData: function (rel) {
      var that = this;
      var apiurl = rel ? that.apiURL[rel] : that.apiurl;
      if (apiurl && apiurl !== "") {
        var url = URI(apiurl);
        if ( rel == "current" ) {
          url = url.search({q: this.search});
        }
        url = url.toString();

        that.loader = true;
        that.$http.get(url)
          .then(function (result) {
            this.apiURL = parseLinkHeader(result.headers.get('Link'));
            that.loader = false;
            this.data = result.data;
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
        console.log("No apiurl");
      }
    },

    currentPage: function () {
      var that = this;
      var page, total;
      var current = that.apiURL['current'];
      if (current && current !== "") {
        var search = URI(current).search(true);
        page = search['page'] || 1;
      } else {
        page = 1;
      }
      var end = that.apiURL['end'];
      if (end && end !== "") {
        var search = URI(end).search(true);
        total = search['page'] || 1;
      } else {
        total = 1;
      }
      return page + " / " + total;
    },

    getLink: function (rel) {
      return this.apiURL[rel];
    }
  }
});
