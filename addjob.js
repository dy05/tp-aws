const AWS = require('aws-sdk');

exports.handler = async (event) => {
  try {
    const dynamoDB = new AWS.DynamoDB({ region: 'us-east-1' });
    const jobTable = 'JOBS';
    const result = await dynamoDB.scan({
      TableName: jobTable,
      Limit: 1,
      ScanIndexForward: false,
    }).promise();
    const previousItem = result?.Items?.length ? result.Items[0] : null;

    let id =  event.body?.id;
    let type =  event.body?.type;

    if (!id) {
      id = (new Date()).getTime().toString();
    }

    if (!type) {
      type = previousItem && previousItem.job_type === 'addToS3' ? ' addToDynamoDB' : 'addToS3';
    }

    let content =  event.body?.content;
    if (!content) {
      content = previousItem && previousItem.job_type === 'addToS3' ? 'un contenu addToDynamoDB' : 'un contenu addToS3'
    }

    const params = {
      TableName: jobTable,
      Item: {
        id: { N: id },
        job_type: { S: type },
        content: { S: content }
      },
    };

    await dynamoDB.putItem(params).promise();
    console.log('Élément ajouté avec succès à la table JOBS');

    return {
      statusCode: 200,
      body: JSON.stringify('OK'),
    };
  } catch (error) {
    console.error("Erreur lors de l'ajout de l'élément à la table JOBS", error);

    return {
      statusCode: 500,
      body: JSON.stringify("Erreur lors de l'ajout de l'élément à la table JOBS"),
    };
  }
};
